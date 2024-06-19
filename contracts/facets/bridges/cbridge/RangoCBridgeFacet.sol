// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import "./im/message/framework/MessageSenderApp.sol";
import "./im/message/framework/MessageReceiverApp.sol";
import "../../../interfaces/IUniswapV2.sol";
import "../../../interfaces/IWETH.sol";
import "./im/interfaces/IMessageBusSender.sol";
import "../../../interfaces/IRangoCBridge.sol";
import "../../../libraries/LibInterchain.sol";
import "../../../interfaces/IRangoMessageReceiver.sol";
import "../../../interfaces/Interchain.sol";
import "../../../utils/ReentrancyGuard.sol";
import "../../../libraries/LibDiamond.sol";
import "../../../libraries/LibPausable.sol";
import {RangoCBridgeMiddleware} from "./RangoCBridgeMiddleware.sol";

/// @title The root contract that handles Rango's interaction with cBridge through a middleware
/// @author George
/// @dev Logic for direct interaction with CBridge is mostly implemented in RangoCBridgeMiddleware contract.
contract RangoCBridgeFacet is IRango, IRangoCBridge, ReentrancyGuard {
    /// Storage ///
    bytes32 internal constant CBRIDGE_NAMESPACE = keccak256("exchange.rango.facets.cbridge");

    struct cBridgeStorage {
        address payable rangoCBridgeMiddlewareAddress;
    }

    /// Constructor

    /// @notice Initialize the contract.
    /// @param rangoCBridgeMiddlewareAddress The address of rango cBridge middleware
    function initCBridge(address payable rangoCBridgeMiddlewareAddress) external {
        LibDiamond.enforceIsContractOwner();
        updateRangoCBridgeMiddlewareAddressInternal(rangoCBridgeMiddlewareAddress);
    }

    /// @notice Enables the contract to receive native ETH token from other contracts including WETH contract
    receive() external payable {}


    /// @notice Emits when the cBridge address is updated
    /// @param oldAddress The previous address
    /// @param newAddress The new address
    event RangoCBridgeMiddlewareAddressUpdated(address oldAddress, address newAddress);

    /// @notice Executes a DEX (arbitrary) call + a cBridge send function
    /// @param request The general swap request containing from/to token and fee/affiliate rewards
    /// @param calls The list of DEX calls, if this list is empty, it means that there is no DEX call and we are only bridging
    /// @dev The cbridge part is handled in the RangoCBridgeMiddleware contract
    /// @dev If this function is success, user will automatically receive the fund in the destination in his/her wallet (receiver)
    /// @dev If bridge is out of liquidity somehow after submiting this transaction and success, user must sign a refund transaction which is not currently present here, will be supported soon
    function cBridgeSwapAndBridge(
        LibSwapper.SwapRequest memory request,
        LibSwapper.Call[] calldata calls,
        CBridgeBridgeRequest calldata bridgeRequest
    ) external payable nonReentrant {
        LibPausable.enforceNotPaused();
        require(getCBridgeStorage().rangoCBridgeMiddlewareAddress != LibSwapper.ETH, "Middleware not set");
        // transfer tokens to middleware if necessary
        uint bridgeAmount;
        if (request.toToken == LibSwapper.ETH && msg.value == 0) {
            uint out = LibSwapper.onChainSwapsPreBridge(request, calls, 0);
            bridgeAmount = out - bridgeRequest.sgnFee;
        }
        else {
            bridgeAmount = LibSwapper.onChainSwapsPreBridge(request, calls, bridgeRequest.sgnFee);
        }
        // transfer tokens to middleware if necessary
        if (request.toToken != LibSwapper.ETH) {
            SafeERC20.safeTransfer(IERC20(request.toToken), getCBridgeStorage().rangoCBridgeMiddlewareAddress, bridgeAmount);
        }

        if (bridgeRequest.bridgeType == CBridgeBridgeType.TRANSFER) {
            require(bridgeRequest.sgnFee == 0, "sgnFee should be 0 for TRANSFER");
            RangoCBridgeMiddleware(getCBridgeStorage().rangoCBridgeMiddlewareAddress).doSend{value : request.toToken == LibSwapper.ETH ? bridgeAmount : 0}(
                    bridgeRequest.receiver,
                    request.toToken,
                    bridgeAmount,
                    bridgeRequest.dstChainId,
                    bridgeRequest.nonce,
                    bridgeRequest.maxSlippage
                );
            // event emission
            emit RangoBridgeInitiated(
                request.requestId,
                request.toToken,
                bridgeAmount,
                bridgeRequest.receiver,
                bridgeRequest.dstChainId,
                false,
                false,
                uint8(BridgeType.CBridge),
                request.dAppTag,
                request.dAppName
            );
        } else {
            // CBridgeIM doesn't support native tokens and we should wrap it.
            if (request.toToken == LibSwapper.ETH) {
                address bridgeImToken = LibSwapper.getBaseSwapperStorage().WETH;
                IWETH(bridgeImToken).deposit{value : bridgeAmount}();
                SafeERC20.safeTransfer(IERC20(bridgeImToken), getCBridgeStorage().rangoCBridgeMiddlewareAddress, bridgeAmount);
            }
            { 
                Interchain.RangoInterChainMessage memory imMessage = abi.decode((bridgeRequest.imMessage), (Interchain.RangoInterChainMessage));
                RangoCBridgeMiddleware(getCBridgeStorage().rangoCBridgeMiddlewareAddress).doCBridgeIM{value : bridgeRequest.sgnFee}(
                    request.toToken == LibSwapper.ETH ? LibSwapper.getBaseSwapperStorage().WETH : request.toToken,
                    bridgeAmount,
                    bridgeRequest.receiver,
                    bridgeRequest.dstChainId,
                    bridgeRequest.nonce,
                    bridgeRequest.maxSlippage,
                    bridgeRequest.sgnFee,
                    imMessage
                );
            }
            // event emission
            emit RangoBridgeInitiated(
                request.requestId,
                request.toToken,
                bridgeAmount,
                bridgeRequest.receiver,
                bridgeRequest.dstChainId,
                true,
                false,
                uint8(BridgeType.CBridge),
                request.dAppTag,
                request.dAppName
            );
        }
    }

    /// @notice Executes a DEX (arbitrary) call + a cBridge send function

    /// @dev The cbridge part is handled in the RangoCBridgeMiddleware contract
    /// @dev If this function is success, user will automatically receive the fund in the destination in his/her wallet (receiver)
    /// @dev If bridge is out of liquidity somehow after submiting this transaction and success, user must sign a refund transaction which is not currently present here, will be supported later
    function cBridgeBridge(
        RangoBridgeRequest memory request,
        CBridgeBridgeRequest calldata bridgeRequest
    ) external payable nonReentrant {
        LibPausable.enforceNotPaused();
        address payable middleware = getCBridgeStorage().rangoCBridgeMiddlewareAddress;
        require(middleware != LibSwapper.ETH, "Middleware not set");
        // transfer tokens to middleware if necessary
        uint value = bridgeRequest.sgnFee;
        if (request.token == LibSwapper.ETH) {
            require(msg.value >= request.amount + bridgeRequest.sgnFee + LibSwapper.sumFees(request), "Insufficient ETH");
            value = request.amount + bridgeRequest.sgnFee;
        } else {
            // To save gas we dont transfer to this contract, instead we directly transfer from user to middleware.
            // Note we only send the amount to middleware (doesn't include fees)
            SafeERC20.safeTransferFrom(IERC20(request.token), msg.sender, middleware, request.amount);
            require(msg.value >= value, "Insufficient ETH");
        }

        // collect fees directly from sender (we save gas by avoiding extra transfers)
        LibSwapper.collectFeesFromSender(request);

        if (bridgeRequest.bridgeType == CBridgeBridgeType.TRANSFER) {
            require(bridgeRequest.sgnFee == 0, "sgnFee should be 0 for TRANSFER");
            RangoCBridgeMiddleware(middleware).doSend{value : value}(
                bridgeRequest.receiver,
                request.token,
                request.amount,
                bridgeRequest.dstChainId,
                bridgeRequest.nonce,
                bridgeRequest.maxSlippage);

            // event emission
            emit RangoBridgeInitiated(
                request.requestId,
                request.token,
                request.amount,
                bridgeRequest.receiver,
                bridgeRequest.dstChainId,
                false,
                false,
                uint8(BridgeType.CBridge),
                request.dAppTag,
                request.dAppName
            );
        } else {
            // CBridgeIM doesn't support native tokens and we should wrap it.
            {
                Interchain.RangoInterChainMessage memory imMessage = abi.decode((bridgeRequest.imMessage), (Interchain.RangoInterChainMessage));
                address bridgeImToken = request.token;
                if (request.token == LibSwapper.ETH) {
                    bridgeImToken = LibSwapper.getBaseSwapperStorage().WETH;
                    IWETH(bridgeImToken).deposit{value : request.amount}();
                    SafeERC20.safeTransfer(IERC20(bridgeImToken), middleware, request.amount);
                }
                require(bridgeImToken != LibSwapper.ETH, "celerIM doesnt support native token");
                RangoCBridgeMiddleware(middleware).doCBridgeIM{value : bridgeRequest.sgnFee}(
                    bridgeImToken,
                    request.amount,
                    bridgeRequest.receiver,
                    bridgeRequest.dstChainId,
                    bridgeRequest.nonce,
                    bridgeRequest.maxSlippage,
                    bridgeRequest.sgnFee,
                    imMessage
                );
            }
            // event emission
            emit RangoBridgeInitiated(
                request.requestId,
                request.token,
                request.amount,
                bridgeRequest.receiver,
                bridgeRequest.dstChainId,
                true,
                false,
                uint8(BridgeType.CBridge),
                request.dAppTag,
                request.dAppName
            );
        }
    }

    function updateRangoCBridgeMiddlewareAddressInternal(address payable newAddress) private {
        require(newAddress != address(0), "Invalid Middleware Address");
        cBridgeStorage storage s = getCBridgeStorage();

        address oldAddress = getRangoCBridgeMiddlewareAddress();
        s.rangoCBridgeMiddlewareAddress = newAddress;

        emit RangoCBridgeMiddlewareAddressUpdated(oldAddress, newAddress);
    }

    function getRangoCBridgeMiddlewareAddress() internal view returns (address) {
        cBridgeStorage storage s = getCBridgeStorage();
        return s.rangoCBridgeMiddlewareAddress;
    }

    /// @dev fetch local storage
    function getCBridgeStorage() private pure returns (cBridgeStorage storage s) {
        bytes32 namespace = CBRIDGE_NAMESPACE;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            s.slot := namespace
        }
    }
}