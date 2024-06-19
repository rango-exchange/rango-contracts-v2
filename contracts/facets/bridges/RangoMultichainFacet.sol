// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import "../../interfaces/IRangoMultichain.sol";
import "../../interfaces/IRango.sol";
import "../../interfaces/IMultichainRouter.sol";
import "../../utils/ReentrancyGuard.sol";
import "../../utils/LibTransform.sol";
import "../../libraries/LibSwapper.sol";
import "../../libraries/LibDiamond.sol";
import "../../libraries/LibInterchain.sol";
import "../../interfaces/Interchain.sol";
import "../../libraries/LibPausable.sol";

/// @title The root contract that handles Rango's interaction with MultichainOrg bridge
/// @author George
contract RangoMultichainFacet is IRango, ReentrancyGuard, IRangoMultichain {
    /// Storage ///
    bytes32 internal constant MULTICHAIN_NAMESPACE = keccak256("exchange.rango.facets.multichain");

    struct MultichainStorage {
        /// @notice List of whitelisted MultichainOrg routers in the current chain
        mapping(address => bool) multichainRouters;
    }

    /// @notice Notifies that some new router addresses are whitelisted
    /// @param _addresses The newly whitelisted addresses
    event MultichainRoutersAdded(address[] _addresses);

    /// @notice Notifies that some router addresses are blacklisted
    /// @param _addresses The addresses that are removed
    event MultichainRoutersRemoved(address[] _addresses);

    /// @notice The constructor of this contract
    /// @param _routers The address of whitelist contracts for bridge routers
    function initMultichain(address[] calldata _routers) external {
        LibDiamond.enforceIsContractOwner();
        addMultichainRoutersInternal(_routers);
    }

    /// @notice Removes a list of routers from the whitelisted addresses
    /// @param _routers The list of addresses that should be deprecated
    function removeMultichainRouters(address[] calldata _routers) external {
        LibDiamond.enforceIsContractOwner();
        MultichainStorage storage s = getMultichainStorage();
        for (uint i = 0; i < _routers.length; i++) {
            delete s.multichainRouters[_routers[i]];
        }
        emit MultichainRoutersRemoved(_routers);
    }

    /// Bridge functions

    /// @notice Executes a DEX (arbitrary) call + a MultichainOrg bridge call
    /// @param request The general swap request containing from/to token and fee/affiliate rewards
    /// @param calls The list of DEX calls, if this list is empty, it means that there is no DEX call and we are only bridging
    /// @param bridgeRequest required data for the bridging step, including the destination chain and recipient wallet address
    function multichainSwapAndBridge(
        LibSwapper.SwapRequest memory request,
        LibSwapper.Call[] calldata calls,
        IRangoMultichain.MultichainBridgeRequest memory bridgeRequest
    ) external payable nonReentrant {
        LibPausable.enforceNotPaused();
        uint out = LibSwapper.onChainSwapsPreBridge(request, calls, 0);
        if (bridgeRequest.bridgeType == MultichainBridgeType.TRANSFER) {
            doMultichainBridge(bridgeRequest, request.toToken, out);
            // event emission
            emit RangoBridgeInitiated(
                request.requestId,
                request.toToken,
                out,
                bridgeRequest.receiverAddress,
                bridgeRequest.receiverChainID,
                false,
                false,
                uint8(BridgeType.Multichain),
                request.dAppTag,
                request.dAppName
            );
        } else {
            doMultichainBridgeAndAnyCall(bridgeRequest, request.toToken, out);
            // event emission
            emit RangoBridgeInitiated(
                request.requestId,
                request.toToken,
                out,
                bridgeRequest.receiverAddress,
                bridgeRequest.receiverChainID,
                true,
                false,
                uint8(BridgeType.Multichain),
                request.dAppTag,
                request.dAppName
            );
        }

    }

    /// @notice Executes a bridge through Multichain
    /// @param request The general swap request containing from/to token and fee/affiliate rewards
    /// @param bridgeRequest required data for the bridging step, including the destination chain and recipient wallet address
    function multichainBridge(
        IRangoMultichain.MultichainBridgeRequest memory request,
        RangoBridgeRequest memory bridgeRequest
    ) external payable nonReentrant {
        LibPausable.enforceNotPaused();
        uint amount = bridgeRequest.amount;
        address token = bridgeRequest.token;
        uint amountWithFee = amount + LibSwapper.sumFees(bridgeRequest);
        if (token != LibSwapper.ETH) {
            SafeERC20.safeTransferFrom(IERC20(token), msg.sender, address(this), amountWithFee);
        } else {
            require(msg.value >= amountWithFee);
        }
        LibSwapper.collectFees(bridgeRequest);
        if (request.bridgeType == MultichainBridgeType.TRANSFER) {
            doMultichainBridge(request, token, amount);
            // event emission
            emit RangoBridgeInitiated(
                bridgeRequest.requestId,
                token,
                amount,
                request.receiverAddress,
                request.receiverChainID,
                false,
                false,
                uint8(BridgeType.Multichain),
                bridgeRequest.dAppTag,
                bridgeRequest.dAppName
            );
        } else {
            Interchain.RangoInterChainMessage memory imMessage = abi.decode((request.imMessage), (Interchain.RangoInterChainMessage));
            doMultichainBridgeAndAnyCall(request, token, amount);
            // event emission
            emit RangoBridgeInitiated(
                bridgeRequest.requestId,
                token,
                amount,
                request.receiverAddress,
                request.receiverChainID,
                true,
                imMessage.actionType != Interchain.ActionType.NO_ACTION,
                uint8(BridgeType.Multichain),
                bridgeRequest.dAppTag,
                bridgeRequest.dAppName
            );
        }
    }

    /// @notice Executes a MultichainOrg bridge call
    /// @param fromToken The address of bridging token
    /// @param inputAmount The amount of the token to be bridged
    /// @param request The other required field by MultichainOrg bridge
    function doMultichainBridge(
        MultichainBridgeRequest memory request,
        address fromToken,
        uint inputAmount
    ) internal {
        if (request.actionType == MultichainActionType.TOKEN_SWAP_OUT) {
            CustomMultichainToken(fromToken).Swapout(inputAmount, request.receiverAddress);
            return;
        } else if (request.actionType == MultichainActionType.TOKEN_TRANSFER) {
            CustomMultichainToken(fromToken).transfer(request.receiverAddress, inputAmount);
            return;
        }

        address routerAddr = request.multichainRouter;
        MultichainStorage storage s = getMultichainStorage();
        require(s.multichainRouters[routerAddr], 'Requested router address not whitelisted');

        if (request.actionType != MultichainActionType.OUT_NATIVE) {
            LibSwapper.approveMax(fromToken, routerAddr, inputAmount);
        } else {
            require(fromToken == LibSwapper.ETH, 'invalid token');
        }

        IMultichainRouter router = IMultichainRouter(routerAddr);

        if (request.actionType == MultichainActionType.OUT) {
            require(request.underlyingToken == fromToken);
            router.anySwapOut(request.underlyingToken, request.receiverAddress, inputAmount, request.receiverChainID);
        } else if (request.actionType == MultichainActionType.OUT_UNDERLYING) {
            require(IUnderlying(request.underlyingToken).underlying() == fromToken);
            router.anySwapOutUnderlying(request.underlyingToken, request.receiverAddress, inputAmount, request.receiverChainID);
        } else if (request.actionType == MultichainActionType.OUT_NATIVE) {
            router.anySwapOutNative{value : inputAmount}(request.underlyingToken, request.receiverAddress, request.receiverChainID);
        } else {
            revert();
        }
    }

    /// @notice Executes a MultichainOrg token bridge and call
    function doMultichainBridgeAndAnyCall(
        MultichainBridgeRequest memory request,
        address fromToken,
        uint inputAmount
    ) internal {
        MultichainStorage storage s = getMultichainStorage();
        require(s.multichainRouters[request.multichainRouter], 'router not allowed');

        if (request.actionType != MultichainActionType.OUT_NATIVE) {
            LibSwapper.approveMax(fromToken, request.multichainRouter, inputAmount);
        } else {
            require(fromToken == LibSwapper.ETH, 'invalid token');
        }

        IMultichainV7Router router = IMultichainV7Router(request.multichainRouter);

        if (request.actionType == MultichainActionType.OUT) {
            router.anySwapOutAndCall(
                request.underlyingToken,
                LibTransform.addressToString(request.receiverAddress),
                inputAmount,
                request.receiverChainID,
                request.anycallTargetContractOnDestChain,
                request.imMessage
            );
        } else if (request.actionType == MultichainActionType.OUT_UNDERLYING) {
            router.anySwapOutUnderlyingAndCall(
                request.underlyingToken,
                LibTransform.addressToString(request.receiverAddress),
                inputAmount,
                request.receiverChainID,
                request.anycallTargetContractOnDestChain,
                request.imMessage
            );
        } else if (request.actionType == MultichainActionType.OUT_NATIVE) {
            router.anySwapOutNativeAndCall{value : inputAmount}(
                request.underlyingToken,
                LibTransform.addressToString(request.receiverAddress),
                request.receiverChainID,
                request.anycallTargetContractOnDestChain,
                request.imMessage
            );
        } else {
            revert();
        }
    }

    function addMultichainRoutersInternal(address[] calldata _addresses) private {
        MultichainStorage storage s = getMultichainStorage();

        address tmpAddr;
        for (uint i = 0; i < _addresses.length; i++) {
            tmpAddr = _addresses[i];
            require(tmpAddr != address(0), "Invalid Router Address");
            s.multichainRouters[tmpAddr] = true;
        }

        emit MultichainRoutersAdded(_addresses);
    }

    /// @dev fetch local storage
    function getMultichainStorage() private pure returns (MultichainStorage storage s) {
        bytes32 namespace = MULTICHAIN_NAMESPACE;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            s.slot := namespace
        }
    }

}