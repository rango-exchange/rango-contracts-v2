// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import "../../interfaces/IWETH.sol";
import "../../interfaces/IRangoConnext.sol";
import "../../interfaces/IRango.sol";
import "../../interfaces/IConnext.sol";
import "../../interfaces/IUniswapV2.sol";
import "../../interfaces/Interchain.sol";
import "../../libraries/LibInterchain.sol";
import "../../utils/LibTransform.sol";
import "../../utils/ReentrancyGuard.sol";
import "../../libraries/LibDiamond.sol";

/// @title The root contract that handles Rango's interaction with Connext
/// @author jeoffery
/// @dev This facet should be added to diamond. This facet doesn't and shouldn't receive messages. Handling messages is done through middleware.
contract RangoConnextFacet is IRango, ReentrancyGuard, IRangoConnext {
    /// Storage ///
    /// @dev keccak256("exchange.rango.facets.connext")
    bytes32 internal constant CONNEXT_NAMESPACE = hex"ae9c2eb5a5d377d0a1adcaaba918ef89101ade4296b0ba754d74ad35f98f7afe";

    struct ConnextStorage {
        /// @notice The address of connext contract
        address connextAddress;
    }

    /// @notice Emitted when the connext address is updated
    /// @param _oldAddress The previous address
    /// @param _newAddress The new address
    event ConnextAddressUpdated(address _oldAddress, address _newAddress);

    /// @notice Emitted when a token bridge request is sent to connext bridge
    /// @param _dstChainId The network id of destination chain, ex: 56 for BSC
    /// @param _token The requested token to bridge
    /// @param _receiver The receiver address in the destination chain
    /// @param _amount The requested amount to bridge
    /// @param _bridgeType simple bridge (0) or transfer with message (1)
    event ConnextBridgeCalled(uint256 _dstChainId, address _token, string _receiver, uint256 _amount, ConnextBridgeType _bridgeType);

    /// @notice Initialize the contract.
    /// @param connextStorage The storage  of whitelist contracts for bridge
    function initConnext(ConnextStorage calldata connextStorage) external {
        LibDiamond.enforceIsContractOwner();
        updateConnextAddressInternal(connextStorage.connextAddress);
    }

    /// @notice Updates the address of connext gateway contract
    /// @param _address The new address of connext gateway contract
    function updateConnextAddress(address _address) public {
        LibDiamond.enforceIsContractOwner();
        updateConnextAddressInternal(_address);
    }

    /// @notice Executes a DEX (arbitrary) call + a connext bridge call
    /// @param request The general swap request containing from/to token and fee/affiliate rewards
    /// @param calls The list of DEX calls, if this list is empty, it means that there is no DEX call and we are only bridging
    /// @param bridgeRequest required data for the bridging step, including the destination chain and recipient wallet address
    function connextSwapAndBridge(
        LibSwapper.SwapRequest memory request,
        LibSwapper.Call[] calldata calls,
        ConnextBridgeRequest memory bridgeRequest
    ) external payable nonReentrant {
        uint out;
        uint bridgeAmount;

        // if toToken is native coin and the user has not paid fee in msg.value,
        // then the user can pay bridge fee using output of swap.
        if (request.toToken == LibSwapper.ETH && msg.value == 0) {
            out = LibSwapper.onChainSwapsPreBridge(request, calls, 0);
            bridgeAmount = out - bridgeRequest.relayerFee;
        } else {
            bridgeAmount = LibSwapper.onChainSwapsPreBridge(request, calls, bridgeRequest.feeInNative ? bridgeRequest.relayerFee : 0);
        }

        // connext xcall() transfers amount and non-native fee separately, we should not consider whole bridge amount as input amount to xcall()
        // because in that situation, not token will be left to covering fee
        if (request.toToken != LibSwapper.ETH && !bridgeRequest.feeInNative) {
            bridgeAmount = bridgeAmount - bridgeRequest.relayerFee;
        }
        
        doConnextBridge(bridgeRequest, request.toToken, bridgeAmount);
        bool hasDestSwap = false;
        if (bridgeRequest.bridgeType == ConnextBridgeType.TRANSFER_WITH_MESSAGE) {
            Interchain.RangoInterChainMessage memory imMessage = abi.decode((bridgeRequest.imMessage), (Interchain.RangoInterChainMessage));
            hasDestSwap = imMessage.actionType != Interchain.ActionType.NO_ACTION;
        }
        // event emission
        emit RangoBridgeInitiated(
            request.requestId,
            request.toToken,
            bridgeAmount,
            bridgeRequest.receiver,
            bridgeRequest.toChainId,
            bridgeRequest.bridgeType == ConnextBridgeType.TRANSFER_WITH_MESSAGE,
            hasDestSwap,
            uint8(BridgeType.Connext),
            request.dAppTag
        );
    }

    /// @notice Executes a bridging via connext
    /// @param request The extra fields required by the connext bridge
    function connextBridge(
        ConnextBridgeRequest memory request,
        RangoBridgeRequest memory bridgeRequest
    ) external payable nonReentrant {
        uint amount = bridgeRequest.amount;
        address token = bridgeRequest.token;
        uint amountWithFee = amount + LibSwapper.sumFees(bridgeRequest);

        {
            uint256 nativeFee = request.feeInNative ? request.relayerFee : 0;
            // transfer tokens if necessary
            if (token != LibSwapper.ETH) {
                SafeERC20.safeTransferFrom(IERC20(token), msg.sender, address(this), amountWithFee + (request.feeInNative ? 0 : request.relayerFee));
                require(msg.value >= nativeFee);
            } else {
                require(msg.value >= amountWithFee + nativeFee);
            }
        }
        LibSwapper.collectFees(bridgeRequest);
        doConnextBridge(request, token, amount);

        bool hasDestSwap = false;
        if (request.bridgeType == ConnextBridgeType.TRANSFER_WITH_MESSAGE) {
            Interchain.RangoInterChainMessage memory imMessage = abi.decode((request.imMessage), (Interchain.RangoInterChainMessage));
            hasDestSwap = imMessage.actionType != Interchain.ActionType.NO_ACTION;
        }
        // event emission
        emit RangoBridgeInitiated(
            bridgeRequest.requestId,
            token,
            amount,
            request.receiver,
            request.destinationDomain,
            request.bridgeType == ConnextBridgeType.TRANSFER_WITH_MESSAGE,
            hasDestSwap,
            uint8(BridgeType.Connext),
            bridgeRequest.dAppTag
        );
    }

    /// @notice Executes a bridging via connext
    /// @param request The extra fields required by the connext bridge
    /// @param token The requested token to bridge
    /// @param amount The requested amount to bridge
    function doConnextBridge(
        ConnextBridgeRequest memory request,
        address token,
        uint256 amount
    ) internal {
        ConnextStorage storage s = getConnextStorage();

        require(s.connextAddress != LibSwapper.ETH, 'Connext address not set');
        require(block.chainid != request.toChainId, 'Invalid destination Chain! Cannot bridge to the same network.');

        LibSwapper.BaseSwapperStorage storage baseStorage = LibSwapper.getBaseSwapperStorage();
        address bridgeToken = token;
        address delegateAddress = request.delegateAddress;
        if (token == LibSwapper.ETH) {
            bridgeToken = baseStorage.WETH;
            IWETH(bridgeToken).deposit{value: amount}();
        }

        if (delegateAddress == LibSwapper.ETH) {
            delegateAddress = msg.sender;
        }
        require(bridgeToken != LibSwapper.ETH, 'Source token address is null! Not supported by connext!');
        LibSwapper.approveMax(bridgeToken, s.connextAddress, amount);
        
        if (request.feeInNative) {
            IConnext(s.connextAddress).xcall{value: request.relayerFee}(
                request.destinationDomain,
                request.receiver,
                bridgeToken,
                delegateAddress,
                amount,
                request.slippage,
                request.imMessage
            );
        } else {
            IConnext(s.connextAddress).xcall(
                request.destinationDomain,
                request.receiver,
                bridgeToken,
                delegateAddress,
                amount,
                request.slippage,
                request.imMessage,
                request.relayerFee
            );
        }
        
        emit ConnextBridgeCalled(request.toChainId, bridgeToken, LibTransform.addressToString(request.receiver), amount, request.bridgeType);
    }

    function updateConnextAddressInternal(address _address) private {
        require(_address != address(0), "Invalid Gateway Address");
        ConnextStorage storage s = getConnextStorage();
        address oldAddress = s.connextAddress;
        s.connextAddress = _address;
        emit ConnextAddressUpdated(oldAddress, _address);
    }

    /// @dev fetch local storage
    function getConnextStorage() private pure returns (ConnextStorage storage s) {
        bytes32 namespace = CONNEXT_NAMESPACE;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            s.slot := namespace
        }
    }
}