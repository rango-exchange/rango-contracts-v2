// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.16;

import "../../interfaces/IRango.sol";
import "../../utils/LibTransform.sol";
import "../../utils/ReentrancyGuard.sol";
import "../../libraries/LibDiamond.sol";
import "../../libraries/LibSwapper.sol";
import "../../interfaces/IAllBridgeRouter.sol";
import "../../interfaces/IRangoAllBridge.sol";

/// @title The root contract that handles Rango's interaction with allbridge
/// @author George
/// @dev This facet should be added to diamond.
contract RangoAllBridgeFacet is IRango, ReentrancyGuard, IRangoAllBridge {
    /// Storage ///
    /// @dev keccak256("exchange.rango.facets.allbridge")
    bytes32 internal constant ALLBRIDGE_NAMESPACE = hex"ca7499307d2f8158acd5d48318ce24f77c0ef835d9c609fad6ea61d3bb4728d7";

    struct AllBridgeStorage {
        /// @notice The address of AllBridge contract on this chain
        address bridgeAddress;
    }

    /// @notice Emitted when the ALlBridge bridge address is updated
    /// @param _oldAddress The previous bridge contract
    /// @param _newAddress The new bridge contract
    event AllBridgeBridgeAddressUpdated(address _oldAddress, address _newAddress);

    /// @notice Updates the address of ALlBridge bridge contract
    /// @param _address The new address of ALlBridge bridge contract
    function updateAllBridgeBridgeAddress(address _address) public {
        LibDiamond.enforceIsContractOwner();
        updateAllBridgeBridgeAddressInternal(_address);
    }

    /// @notice Executes a DEX (arbitrary) call + a AllBridge bridge call
    /// @param request The general swap request containing from/to token and fee/affiliate rewards
    /// @param calls The list of DEX calls, if this list is empty, it means that there is no DEX call and we are only bridging
    /// @param bridgeRequest required data for the bridging step, including the destination chain and recipient wallet address
    function allbridgeSwapAndBridge(
        LibSwapper.SwapRequest memory request,
        LibSwapper.Call[] calldata calls,
        AllBridgeRequest memory bridgeRequest
    ) external payable nonReentrant {
        uint out = LibSwapper.onChainSwapsPreBridge(request, calls, bridgeRequest.transferFee);

        doAllBridgeBridge(bridgeRequest, request.toToken, out);
        // event emission
        emit RangoBridgeInitiated(
            request.requestId,
            request.toToken,
            out,
            LibTransform.bytes32LeftPaddedToAddress(bridgeRequest.recipient),
            bridgeRequest.destinationChainId,
            false,
            false,
            uint8(BridgeType.AllBridge),
            request.dAppTag
        );
    }

    /// @notice Executes a bridging via allbridge
    /// @param request The extra fields required by the allbridge
    function allbridgeBridge(
        AllBridgeRequest memory request,
        RangoBridgeRequest memory bridgeRequest
    ) external payable nonReentrant {
        uint amount = bridgeRequest.amount;
        address token = bridgeRequest.token;
        uint amountWithFee = amount + LibSwapper.sumFees(bridgeRequest);
        // transfer tokens if necessary
        if (token != LibSwapper.ETH) {
            SafeERC20.safeTransferFrom(IERC20(token), msg.sender, address(this), amountWithFee);
            require(msg.value >= request.transferFee);
        } else {
            require(msg.value >= amountWithFee);
        }
        LibSwapper.collectFees(bridgeRequest);
        doAllBridgeBridge(request, token, amount);
        // event emission
        emit RangoBridgeInitiated(
            bridgeRequest.requestId,
            token,
            amount,
            LibTransform.bytes32LeftPaddedToAddress(request.recipient),
            request.destinationChainId,
            false,
            false,
            uint8(BridgeType.AllBridge),
            bridgeRequest.dAppTag
        );
    }

    /// @notice Executes a bridging via allBridge
    /// @param request The extra fields required by the allbridge
    /// @param token The requested token to bridge
    /// @param amount The requested amount to bridge
    function doAllBridgeBridge(
        AllBridgeRequest memory request,
        address token,
        uint256 amount
    ) internal {
        AllBridgeStorage storage s = getAllBridgeStorage();
        require(s.bridgeAddress != LibSwapper.ETH, 'AllBridge bridge address not set');
        require(token != LibSwapper.ETH, 'native token bridging not implemented');

        IAllBridgeRouter bridge = IAllBridgeRouter(s.bridgeAddress);
        // get the pool address and approve for it
        bytes32 tokenAddressLeftPadded = LibTransform.addressToBytes32LeftPadded(token);

        address poolAddress = bridge.pools(tokenAddressLeftPadded);
        require(poolAddress != LibSwapper.ETH, 'PoolAddress does not exist');
        LibSwapper.approve(token, poolAddress, amount);

        bridge.swapAndBridge{value : request.transferFee}(
            tokenAddressLeftPadded,
            amount,
            request.recipient,
            request.destinationChainId,
            request.receiveTokenAddress,
            request.nonce,
            request.messenger
        );

    }

    function updateAllBridgeBridgeAddressInternal(address _address) private {
        require(_address != address(0), "Invalid AllBridge Address");
        AllBridgeStorage storage s = getAllBridgeStorage();
        address oldAddress = s.bridgeAddress;
        s.bridgeAddress = _address;
        emit AllBridgeBridgeAddressUpdated(oldAddress, _address);
    }

    /// @dev fetch local storage
    function getAllBridgeStorage() private pure returns (AllBridgeStorage storage s) {
        bytes32 namespace = ALLBRIDGE_NAMESPACE;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            s.slot := namespace
        }
    }
}