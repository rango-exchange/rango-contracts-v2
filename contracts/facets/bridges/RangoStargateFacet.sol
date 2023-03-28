// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.16;

import "../../interfaces/IUniswapV2.sol";
import "../../interfaces/IWETH.sol";
import "../../interfaces/IRangoStargate.sol";
import "../../interfaces/IStargateReceiver.sol";
import "../../interfaces/IStargateWidget.sol";
import "../../interfaces/Interchain.sol";
import "../../libraries/LibInterchain.sol";
import "../../interfaces/IRangoMessageReceiver.sol";
import "../../interfaces/IRango.sol";
import "../../utils/ReentrancyGuard.sol";
import "../../utils/LibTransform.sol";
import "../../libraries/LibDiamond.sol";
import "../../utils/LibTransform.sol";

/// @title The root contract that handles Rango's interaction with Stargate. For receiving messages from LayerZero, a middleware contract is used(RangoStargateMiddleware).
/// @author Uchiha Sasuke
contract RangoStargateFacet is IRango, ReentrancyGuard, IRangoStargate {
    /// Storage ///
    /// @dev keccak256("exchange.rango.facets.stargate")
    bytes32 internal constant STARGATE_NAMESPACE = hex"9226eefa91acf770d80880f45d613abe38399c942d4a127aff5bb29333e9d4a5";

    struct StargateStorage {
        /// @notice The address of stargate contract
        address stargateRouter;
        address stargateRouterEth;
        address stargateWidget;
        bytes2 partnerId;
    }

    /// @notice Initialize the contract.
    /// @param addresses The new addresses of Stargate contracts
    function initStargate(StargateStorage calldata addresses) external {
        LibDiamond.enforceIsContractOwner();
        updateStargateAddressInternal(addresses.stargateRouter, addresses.stargateRouterEth);
        updateStargateWidgetInternal(addresses.stargateWidget, addresses.partnerId);
    }

    /// @notice Enables the contract to receive native ETH token from other contracts including WETH contract
    receive() external payable {}

    /// @notice Emits when the stargate router address is updated
    /// @param _oldRouter The previous router address
    /// @param _oldRouterEth The previous routerEth address
    /// @param _newRouter The new router address
    /// @param _newRouterEth The new routerEth address
    event StargateAddressUpdated(address _oldRouter, address _oldRouterEth, address _newRouter, address _newRouterEth);
    /// @notice Emits when the stargate widget address is updated
    /// @param _widgetAddress The widget address of stargate
    /// @param _partnerId The partnerId of stargate
    event StargateWidgetUpdated(address _widgetAddress, bytes2 _partnerId);

    /// @notice Updates the address of Stargate contract
    /// @param _router The new address of Stargate contract
    /// @param _routerEth The new address of Stargate contract
    function updateStargateAddress(address _router, address _routerEth) public {
        LibDiamond.enforceIsContractOwner();
        updateStargateAddressInternal(_router, _routerEth);
    }
    /// @notice Updates the address of Stargate contract
    /// @param _widgetAddress The new address of Stargate contract
    /// @param _partnerId The new address of Stargate contract
    function updateStargateWidget(address _widgetAddress, bytes2 _partnerId) public {
        LibDiamond.enforceIsContractOwner();
        updateStargateWidgetInternal(_widgetAddress, _partnerId);
    }

    function stargateSwapAndBridge(
        LibSwapper.SwapRequest memory request,
        LibSwapper.Call[] calldata calls,
        IRangoStargate.StargateRequest memory stargateRequest
    ) external payable nonReentrant {
        uint out;
        uint bridgeAmount;
        // if toToken is native coin and the user has not paid fee in msg.value,
        // then the user can pay bridge fee using output of swap.
        if (request.toToken == LibSwapper.ETH && msg.value == 0) {
            out = LibSwapper.onChainSwapsPreBridge(request, calls, 0);
            bridgeAmount = out - stargateRequest.stgFee;
        }
        else {
            out = LibSwapper.onChainSwapsPreBridge(request, calls, stargateRequest.stgFee);
            bridgeAmount = out;
        }
        doStargateSwap(stargateRequest, request.toToken, bridgeAmount);

        bool hasDestSwap = false;
        if (stargateRequest.bridgeType == StargateBridgeType.TRANSFER_WITH_MESSAGE) {
            Interchain.RangoInterChainMessage memory imMessage = abi.decode((stargateRequest.imMessage), (Interchain.RangoInterChainMessage));
            hasDestSwap = imMessage.actionType != Interchain.ActionType.NO_ACTION;
        }

        // event emission
        emit RangoBridgeInitiated(
            request.requestId,
            request.toToken,
            out,
            LibTransform.bytesToAddress(stargateRequest.to),
            stargateRequest.dstChainId,
            stargateRequest.bridgeType == StargateBridgeType.TRANSFER_WITH_MESSAGE,
            hasDestSwap,
            uint8(BridgeType.Stargate),
            request.dAppTag
        );
    }

    function stargateBridge(
        IRangoStargate.StargateRequest memory stargateRequest,
        RangoBridgeRequest memory bridgeRequest
    ) external payable nonReentrant {
        uint256 amountWithFee = bridgeRequest.amount + LibSwapper.sumFees(bridgeRequest);
        // transfer tokens if necessary
        if (bridgeRequest.token != LibSwapper.ETH) {
            SafeERC20.safeTransferFrom(IERC20(bridgeRequest.token), msg.sender, address(this), amountWithFee);
            require(msg.value >= stargateRequest.stgFee, "Insufficient ETH sent for bridging");
        } else {
            require(msg.value >= amountWithFee + stargateRequest.stgFee, "Insufficient ETH sent for bridging");
        }
        LibSwapper.collectFees(bridgeRequest);
        doStargateSwap(stargateRequest, bridgeRequest.token, bridgeRequest.amount);

        bool hasDestSwap = false;
        if (stargateRequest.bridgeType == StargateBridgeType.TRANSFER_WITH_MESSAGE) {
            Interchain.RangoInterChainMessage memory imMessage = abi.decode((stargateRequest.imMessage), (Interchain.RangoInterChainMessage));
            hasDestSwap = imMessage.actionType != Interchain.ActionType.NO_ACTION;
        }
        // event emission
        emit RangoBridgeInitiated(
            bridgeRequest.requestId,
            bridgeRequest.token,
            bridgeRequest.amount,
            LibTransform.bytesToAddress(stargateRequest.to),
            stargateRequest.dstChainId,
            stargateRequest.bridgeType == StargateBridgeType.TRANSFER_WITH_MESSAGE,
            hasDestSwap,
            uint8(BridgeType.Stargate),
            bridgeRequest.dAppTag
        );
    }

    /// @notice Executes a Stargate call
    /// @param request Required bridge params + interchain message that contains all the required info on the destination
    /// @param fromToken The address of source token to bridge
    /// @param inputAmount The amount to be bridged (excluding the fee)
    function doStargateSwap(
        StargateRequest memory request,
        address fromToken,
        uint256 inputAmount
    ) internal {
        StargateStorage storage s = getStargateStorage();

        address router = fromToken == LibSwapper.ETH ? s.stargateRouterEth : s.stargateRouter;
        require(router != LibSwapper.ETH, "Stargate router address not set");

        if (fromToken != LibSwapper.ETH) {
            LibSwapper.approveMax(fromToken, router, inputAmount);
        }

        bytes memory payload = request.bridgeType == StargateBridgeType.TRANSFER_WITH_MESSAGE
        ? request.imMessage
        : new bytes(0);

        if (fromToken == LibSwapper.ETH) {
            if (request.bridgeType == StargateBridgeType.TRANSFER_WITH_MESSAGE) {
                revert("Payload not supported on swapETH");
            }
            stargateRouterSwapEth(request, router, inputAmount);
        } else {
            stargateRouterSwap(request, router, inputAmount, request.stgFee, payload);
        }
        if (s.stargateWidget != LibSwapper.ETH) {
            IStargateWidget(s.stargateWidget).partnerSwap(s.partnerId);
        }
    }

    function stargateRouterSwapEth(StargateRequest memory request, address router, uint256 bridgeAmount) private {
        IStargateRouter(router).swapETH{value : bridgeAmount + request.stgFee}(
            request.dstChainId,
            request.srcGasRefundAddress,
            request.to,
            bridgeAmount,
            request.minAmountLD
        );
    }

    function stargateRouterSwap(
        StargateRequest memory request,
        address router,
        uint256 inputAmount,
        uint256 value,
        bytes memory payload
    ) private {
        IStargateRouter.lzTxObj memory lzTx = IStargateRouter.lzTxObj(
            request.dstGasForCall,
            request.dstNativeAmount,
            request.dstNativeAddr
        );
        IStargateRouter(router).swap{value : value}(
            request.dstChainId,
            request.srcPoolId,
            request.dstPoolId,
            request.srcGasRefundAddress,
            inputAmount,
            request.minAmountLD,
            lzTx,
            request.to,
            payload
        );
    }

    function updateStargateAddressInternal(address _router, address _routerEth) private {
        require(_router != address(0), "Invalid router Address");
        require(_routerEth != address(0), "Invalid routerEth Address");
        StargateStorage storage s = getStargateStorage();
        address oldAddressRouter = s.stargateRouter;
        s.stargateRouter = _router;

        address oldAddressRouterEth = s.stargateRouterEth;
        s.stargateRouterEth = _routerEth;

        emit StargateAddressUpdated(oldAddressRouter, oldAddressRouterEth, _router, _routerEth);
    }

    function updateStargateWidgetInternal(address _widgetAddress, bytes2 _partnerId) private {
        StargateStorage storage s = getStargateStorage();
        s.stargateWidget = _widgetAddress;
        s.partnerId = _partnerId;

        emit StargateWidgetUpdated(_widgetAddress, _partnerId);
    }

    /// @dev fetch local storage
    function getStargateStorage() private pure returns (StargateStorage storage s) {
        bytes32 namespace = STARGATE_NAMESPACE;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            s.slot := namespace
        }
    }
}