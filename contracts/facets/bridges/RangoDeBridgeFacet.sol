// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import "../../interfaces/IRango.sol";
import "../../interfaces/IRangoDeBridge.sol";
import "../../interfaces/IDeBridge.sol";
import "../../interfaces/Interchain.sol";
import "../../utils/LibTransform.sol";
import "../../utils/ReentrancyGuard.sol";
import "../../libraries/LibDiamond.sol";

/// @title The root contract that handles Rango's interaction with deBridge via DLN tool (DeSwap Liquidity Network)
/// @author jeoffery
/// @dev This facet should be added to diamond. This facet doesn't and shouldn't receive messages. Handling messages is done through middleware.
contract RangoDeBridgeFacet is IRango, ReentrancyGuard, IRangoDeBridge {
    /// Storage ///
    /// @dev keccak256("exchange.rango.facets.deBridge")
    bytes32 internal constant DEBRIDGE_NAMESPACE = hex"e551b477704d1635aa3f65d1252b54961348b6408b6cb32ae166e6f2870394e1";

    struct DeBridgeStorage {
        /// @notice The address of dln source to initiate bridge
        address dlnSourceAddress;
    }

    /// @notice Emitted when the DlnSource address is updated
    /// @param _oldAddress The previous address
    /// @param _newAddress The new address
    event DeBridgeDlnSourceAddressUpdated(address _oldAddress, address _newAddress);

    /// @notice Emitted when an ERC20 token (non-native) bridge request is sent to deBridge
    /// @param _dstChainId The network id of destination chain, ex: 56 for BSC
    /// @param _token The requested token to bridge
    /// @param _receiver The receiver address in the destination chain
    /// @param _amount The requested amount to bridge
    /// @param _type simple transfer or with message
    event DeBridgeSendTokenCalled(uint256 _dstChainId, address _token, string _receiver, uint256 _amount, DeBridgeBridgeType _type);

    /// @notice Initialize the contract.
    /// @param dlnSourceAddress The address of dlnSource contract
    function initDeBridge(address dlnSourceAddress) external {
        LibDiamond.enforceIsContractOwner();
        updateDlnSourceInternal(dlnSourceAddress);
    }

    /// @notice Updates the address of dlnSource contract
    /// @param _address The new address of dlnSource contract
    function updateDlnSourceAddress(address _address) public {
        LibDiamond.enforceIsContractOwner();
        updateDlnSourceInternal(_address);
    }

    /// @notice Executes a DEX (arbitrary) call + a deBridge bridge call
    /// @param request The general swap request containing from/to token and fee/affiliate rewards
    /// @param calls The list of DEX calls, if this list is empty, it means that there is no DEX call and we are only bridging
    /// @param bridgeRequest required data for the bridging step, including the destination chain and recipient wallet address
    function deBridgeSwapAndBridge(
        LibSwapper.SwapRequest memory request,
        LibSwapper.Call[] calldata calls,
        DeBridgeRequest memory bridgeRequest
    ) external payable nonReentrant {
        uint bridgeAmount;
        // if toToken is native coin and the user has not paid fee in msg.value,
        // then the user can pay bridge fee using output of swap.
        if (request.toToken == LibSwapper.ETH && msg.value == 0) {
            bridgeAmount = LibSwapper.onChainSwapsPreBridge(request, calls, 0) - bridgeRequest.protocolFee;
        }
        else {
            bridgeAmount = LibSwapper.onChainSwapsPreBridge(request, calls, bridgeRequest.protocolFee);
        }

        // update giveAmount using actual output amount of swaps.
        bridgeRequest.orderCreation.giveAmount = bridgeAmount;

        doDeBridgeBridge(bridgeRequest, request.toToken, bridgeAmount);

        // event emission
        emit RangoBridgeInitiated(
            request.requestId,
            request.toToken,
            bridgeAmount,
            LibTransform.bytesToAddress(bridgeRequest.orderCreation.receiverDst),
            bridgeRequest.orderCreation.takeChainId,
            bridgeRequest.bridgeType == DeBridgeBridgeType.TRANSFER_WITH_MESSAGE,
            bridgeRequest.hasDestSwap,
            uint8(BridgeType.DeBridge),
            request.dAppTag,
            request.dAppName
        );
    }

    /// @notice Executes a bridging via deBridge
    /// @param request The extra fields required by the deBridge
    function deBridgeBridge(
        DeBridgeRequest memory request,
        RangoBridgeRequest memory bridgeRequest
    ) external payable nonReentrant {
        uint amount = bridgeRequest.amount;
        address token = bridgeRequest.token;
        uint amountWithFee = amount + LibSwapper.sumFees(bridgeRequest);
        // transfer tokens if necessary
        if (token != LibSwapper.ETH) {
            SafeERC20.safeTransferFrom(IERC20(token), msg.sender, address(this), amountWithFee);
            require(msg.value >= request.protocolFee);
        } else {
            require(msg.value >= amountWithFee + request.protocolFee);
        }
        LibSwapper.collectFees(bridgeRequest);
        doDeBridgeBridge(request, token, amount);

        // event emission
        emit RangoBridgeInitiated(
            bridgeRequest.requestId,
            token,
            amount,
            LibTransform.bytesToAddress(request.orderCreation.receiverDst),
            request.orderCreation.takeChainId,
            request.bridgeType == DeBridgeBridgeType.TRANSFER_WITH_MESSAGE,
            request.hasDestSwap,
            uint8(BridgeType.DeBridge),
            bridgeRequest.dAppTag,
            bridgeRequest.dAppName
        );
    }

    /// @notice Executes a bridging via deBridge
    /// @param request The extra fields required by deBridge
    /// @param token The requested token to bridge
    /// @param amount The requested amount to bridge
    function doDeBridgeBridge(
        DeBridgeRequest memory request,
        address token,
        uint256 amount
    ) internal {
        DeBridgeStorage storage s = getDeBridgeStorage();
        uint dstChainId = request.orderCreation.takeChainId;

        require(s.dlnSourceAddress != LibSwapper.ETH, 'DlnSource contract address not set');
        require(block.chainid != dstChainId, 'Invalid dst Chain! Cannot bridge to the same network.');

        if (token != LibSwapper.ETH) {
            LibSwapper.approveMax(token, s.dlnSourceAddress, amount);
        }

        IDlnSource(s.dlnSourceAddress).createSaltedOrder{value: token == LibSwapper.ETH ? amount + request.protocolFee : request.protocolFee}(
            request.orderCreation,
            request.salt,
            request.affiliateFee,
            request.referralCode,
            request.permitEnvelope,
            request.metadata
        );

        emit DeBridgeSendTokenCalled(dstChainId, token, string(request.orderCreation.receiverDst), amount, request.bridgeType);
    }

    function updateDlnSourceInternal(address _address) private {
        require(_address != address(0), "Invalid dlnSource Address");
        DeBridgeStorage storage s = getDeBridgeStorage();
        address oldAddress = s.dlnSourceAddress;
        s.dlnSourceAddress = _address;
        emit DeBridgeDlnSourceAddressUpdated(oldAddress, _address);
    }

    /// @dev fetch local storage
    function getDeBridgeStorage() private pure returns (DeBridgeStorage storage s) {
        bytes32 namespace = DEBRIDGE_NAMESPACE;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            s.slot := namespace
        }
    }
}