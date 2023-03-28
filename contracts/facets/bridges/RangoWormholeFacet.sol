// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.16;

import "../../interfaces/IWETH.sol";
import "../../interfaces/IRangoWormhole.sol";
import "../../interfaces/IRango.sol";
import "../../interfaces/IWormholeRouter.sol";
import "../../interfaces/IWormholeTokenBridge.sol";
import "../../interfaces/WormholeBridgeStructs.sol";
import "../../utils/ReentrancyGuard.sol";
import "../../libraries/LibSwapper.sol";
import "../../libraries/LibDiamond.sol";
import "../../interfaces/Interchain.sol";

/// @title The root contract that handles Rango's interaction with wormhole
/// @author AMA
contract RangoWormholeFacet is IRango, ReentrancyGuard, IRangoWormhole {

    /// Storage ///
    /// @dev keccak256("exchange.rango.facets.wormhole")
    bytes32 internal constant WORMHOLE_NAMESPACE = hex"793f7e3915857b52a2ca33e83f8b2c68a049de66d28e53738de96c395c5ad94d";

    struct WormholeStorage {
        /// @notice The address of wormhole contract
        address wormholeRouter;
    }

    /// @notice Emits when the wormhole address is updated
    /// @param _oldAddress The previous address
    /// @param _newAddress The new address
    event WormholeAddressUpdated(address _oldAddress, address _newAddress);

    /// @notice Initialize the contract.
    /// @param wormholeRouter The contract address of wormhole contract.
    function initWormhole(address wormholeRouter) external {
        LibDiamond.enforceIsContractOwner();
        updateWormholeAddressInternal(wormholeRouter);
    }

    /// @notice Updates the address of wormhole contract
    /// @param _address The new address of wormhole contract
    function updateWormholeAddress(address _address) public {
        LibDiamond.enforceIsContractOwner();
        updateWormholeAddressInternal(_address);
    }

    /// @notice Executes a DEX (arbitrary) call + a wormhole bridge function
    /// @param request The general swap request containing from/to token and fee/affiliate rewards
    /// @param calls The list of DEX calls, if this list is empty, it means that there is no DEX call and we are only bridging
    /// @param bridgeRequest data related to wormhole bridge
    /// @dev The wormhole bridge part is handled in the RangoWormhole.sol contract
    /// @dev If this function is a success, user will automatically receive the fund in the destination in their wallet (receiver)
    function wormholeSwapAndBridge(
        LibSwapper.SwapRequest memory request,
        LibSwapper.Call[] calldata calls,
        IRangoWormhole.WormholeBridgeRequest memory bridgeRequest
    ) external payable nonReentrant {
        uint out = LibSwapper.onChainSwapsPreBridge(request, calls, 0);
        uint bridgeAmount = out - bridgeRequest.fee;
        doWormholeBridge(bridgeRequest, request.toToken, bridgeAmount);

        bool hasInterchainMessage = false;
        bool hasDestSwap = false;
        if (bridgeRequest.bridgeType == WormholeBridgeType.TRANSFER_WITH_MESSAGE) {
            hasInterchainMessage = true;
            Interchain.RangoInterChainMessage memory imMessage = abi.decode((bridgeRequest.imMessage), (Interchain.RangoInterChainMessage));
            hasDestSwap = imMessage.actionType != Interchain.ActionType.NO_ACTION;
        }

        // event emission
        emit RangoBridgeInitiated(
            request.requestId,
            request.toToken,
            bridgeAmount,
            address(uint160(bytes20(bridgeRequest.recipient))),
            bridgeRequest.recipientChain,
            hasInterchainMessage,
            hasDestSwap,
            uint8(BridgeType.Wormhole),
            request.dAppTag
        );
    }

    /// @notice Executes a wormhole bridge function
    /// @param request data related to wormhole bridge
    /// @param bridgeRequest data related to wormhole bridge
    function wormholeBridge(
        IRangoWormhole.WormholeBridgeRequest memory request,
        IRango.RangoBridgeRequest memory bridgeRequest
    ) external payable nonReentrant {
        uint256 amountWithFee = bridgeRequest.amount + LibSwapper.sumFees(bridgeRequest);
        // transfer tokens if necessary
        if (bridgeRequest.token == LibSwapper.ETH) {
            require(msg.value >= amountWithFee + request.fee, "Insufficient ETH");
        } else {
            SafeERC20.safeTransferFrom(IERC20(bridgeRequest.token), msg.sender, address(this), amountWithFee + request.fee);
        }

        LibSwapper.collectFees(bridgeRequest);
        doWormholeBridge(request, bridgeRequest.token, bridgeRequest.amount);

        bool hasInterchainMessage = false;
        bool hasDestSwap = false;
        if (request.bridgeType == WormholeBridgeType.TRANSFER_WITH_MESSAGE) {
            hasInterchainMessage = true;
            Interchain.RangoInterChainMessage memory imMessage = abi.decode((request.imMessage), (Interchain.RangoInterChainMessage));
            hasDestSwap = imMessage.actionType != Interchain.ActionType.NO_ACTION;
        }

        // event emission
        emit RangoBridgeInitiated(
            bridgeRequest.requestId,
            bridgeRequest.token,
            bridgeRequest.amount,
            address(uint160(bytes20(request.recipient))),
            request.recipientChain,
            hasInterchainMessage,
            hasDestSwap,
            uint8(BridgeType.Wormhole),
            bridgeRequest.dAppTag
        );
    }

    /// @notice Executes a bridging via wormhole
    /// @param request The extra fields required by the wormhole bridge
    /// @param token The requested token to bridge
    /// @param amount The requested amount to bridge
    function doWormholeBridge(
        IRangoWormhole.WormholeBridgeRequest memory request,
        address token,
        uint256 amount
    ) internal {
        WormholeStorage storage s = getWormholeStorage();
        require(s.wormholeRouter != LibSwapper.ETH, 'Wormhole address not set');

        if (request.bridgeType == WormholeBridgeType.TRANSFER_WITH_MESSAGE) {
            if (token == LibSwapper.ETH) {
                IWormholeRouter(s.wormholeRouter).wrapAndTransferETHWithPayload{value : amount}(
                    request.recipientChain,
                    request.recipient,
                    request.nonce,
                    request.imMessage
                );
            } else {
                LibSwapper.approveMax(token, s.wormholeRouter, amount);
                IWormholeRouter(s.wormholeRouter).transferTokensWithPayload(
                    token,
                    amount,
                    request.recipientChain,
                    request.recipient,
                    request.nonce,
                    request.imMessage
                );
            }
        } else {
            if (token == LibSwapper.ETH) {
                IWormholeRouter(s.wormholeRouter).wrapAndTransferETH{value : amount + request.fee}(
                    request.recipientChain,
                    request.recipient,
                    request.fee,
                    request.nonce
                );
            } else {
                LibSwapper.approveMax(token, s.wormholeRouter, amount + request.fee);
                IWormholeRouter(s.wormholeRouter).transferTokens(
                    token,
                    amount + request.fee,
                    request.recipientChain,
                    request.recipient,
                    request.fee,
                    request.nonce
                );
            }
        }
    }

    function updateWormholeAddressInternal(address _address) private {
        require(_address != address(0), "Invalid Wormhole Address");
        WormholeStorage storage s = getWormholeStorage();
        address oldAddress = s.wormholeRouter;
        s.wormholeRouter = _address;
        emit WormholeAddressUpdated(oldAddress, _address);
    }

    /// @dev fetch local storage
    function getWormholeStorage() private pure returns (WormholeStorage storage s) {
        bytes32 namespace = WORMHOLE_NAMESPACE;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            s.slot := namespace
        }
    }
}