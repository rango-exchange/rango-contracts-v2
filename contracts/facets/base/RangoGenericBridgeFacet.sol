// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import "../../libraries/LibDiamond.sol";
import "../../libraries/LibSwapper2.sol";
import "../../utils/ReentrancyGuard.sol";
import "../../libraries/LibPausable.sol";
import "../../interfaces/IRango2.sol";

contract RangoGenericBridgeFacet is IRango2, ReentrancyGuard {
    
    struct BridgeCalls {
        address target;
        address spender; 
        bytes data;
        uint256 startIndexForAmount;
        uint256 nativeValueToSend;
        bool valueIsBridgeAmount;
    }

    struct GenericBridgeRequest {
        uint8 bridgeId;
        BridgeCalls[] calls;
        address reciepent;
        uint256 dstChainId;
        bool hasInterchainMessage;
        bool hasDestinationSwap;
        uint256 extraFee;
        int256 extraERC20Fee;
    }

    error GenericBridge__TargetNotWhitelisted(address _target, bytes4 _selector);
    error GenericBridge__InputLengthMissmatch();
    error GenericBridge__InvalidStartIndex();

    /// @notice Does a simple on-chain swap
    /// @param request The general swap request containing from/to token and fee/affiliate rewards
    /// @param calls The list of DEX calls
    /// @param receiver The address that should receive the output of swaps.
    /// @return The byte array result of all DEX calls
    function onChainSwaps(
        LibSwapper2.SwapRequest memory request,
        LibSwapper2.Call[] calldata calls,
        address receiver
    ) external payable nonReentrant returns (bytes[] memory) {
        LibPausable.enforceNotPaused();
        require(receiver != LibSwapper2.ETH, "receiver cannot be address(0)");
        (bytes[] memory result, uint outputAmount) = LibSwapper2.onChainSwapsInternal(request, calls, 0);
        LibSwapper2.emitSwapEvent(request, outputAmount, receiver);
        LibSwapper2._sendToken(request.toToken, outputAmount, receiver, false);
        return result;
    }

    /// @notice Performs a swap followed by a generic bridge operation
    /// @param request The swap request containing details of the token to swap from and to, including fees
    /// @param calls The list of DEX calls to execute the swap
    /// @param bridgeRequest The bridge request containing details of the bridging operation
    function genericSwapAndBridge(
        LibSwapper2.SwapRequest memory request,
        LibSwapper2.Call[] calldata calls,
        GenericBridgeRequest memory bridgeRequest
    ) external payable nonReentrant {
        uint256 bridgeAmount;
        if (request.toToken == LibSwapper2.ETH && msg.value == 0) {
            bridgeAmount = LibSwapper2.onChainSwapsPreBridge(request, calls, 0) - bridgeRequest.extraFee;
        } else {
            bridgeAmount = LibSwapper2.onChainSwapsPreBridge(request, calls, bridgeRequest.extraFee);
        }
        // overwrite the calldata/native value amount with swap result
        overwriteAmount(bridgeAmount, bridgeRequest);

        // dobridge
        doGenericBridge(bridgeRequest, request.toToken, bridgeAmount);

        // emit bridge init event
        emit RangoBridgeInitiated(
            request.requestId,
            request.toToken,
            bridgeAmount,
            bridgeRequest.reciepent,
            bridgeRequest.dstChainId,
            bridgeRequest.hasInterchainMessage,
            bridgeRequest.hasDestinationSwap,
            bridgeRequest.bridgeId, //bridgeId
            request.dAppTag,
            request.dAppName
        );
    }
    
    /// @notice Executes a generic bridge operation
    /// @param bridgeRequest The bridge request containing details of the bridging operation
    /// @param request The Rango bridge request containing token and amount details
    function genericBridge(GenericBridgeRequest memory bridgeRequest, IRango2.RangoBridgeRequest memory request)
        external
        payable
        nonReentrant
    {
        LibPausable.enforceNotPaused();
        // fee calculations
        address token = request.token;
        uint256 amountWithFee = request.amount + LibSwapper2.sumFees(request);

        // transfer initial amount of erc20 or eth to address(this)
        if (token == LibSwapper2.ETH) {
            require(msg.value >= amountWithFee, "Insufficient ETH sent for bridging and fees");
        } else {
            SafeERC20.safeTransferFrom(IERC20(token), msg.sender, address(this), amountWithFee);
        }
        // collect fees
        LibSwapper2.collectFees(request);

        // dobridge
        doGenericBridge(bridgeRequest, request.token, request.amount);

        // emit bridge init event
        emit RangoBridgeInitiated(
            request.requestId,
            request.token,
            request.amount,
            bridgeRequest.reciepent,
            bridgeRequest.dstChainId,
            bridgeRequest.hasInterchainMessage,
            bridgeRequest.hasDestinationSwap,
            bridgeRequest.bridgeId, //bridgeId
            request.dAppTag,
            request.dAppName
        );
    }

    /// Internal Functions ///
    function doGenericBridge(GenericBridgeRequest memory request, address token, uint256 amount) internal {
        LibSwapper2.BaseSwapperStorage storage baseSwapperStorage = LibSwapper2.getBaseSwapperStorage();

        //check if length of target, data and nativeValueToSend are the same
        uint256 callsLength = request.calls.length;

        //loop through the targets and call them
        for (uint256 i; i < callsLength;) {
            //check if the target/selector are whitelisted
            bytes memory callData = request.calls[i].data;
            require(callData.length >= 4, "Invalid calldata");
            bytes4 selector;
            assembly {
                selector := mload(add(callData, 32))
            }
            address target = request.calls[i].target;
            address spender = request.calls[i].spender;
            if (
                baseSwapperStorage.whitelistContracts[target] == false
                    || baseSwapperStorage.whitelistMethods[target][selector] == false
            ) {
                revert GenericBridge__TargetNotWhitelisted(target, selector);
            }
            if (baseSwapperStorage.whitelistContracts[spender] == false) {
                revert GenericBridge__TargetNotWhitelisted(spender, bytes4(0));
            }
            //approve max token if is not native or already approved
            if (token != LibSwapper2.ETH) {
                LibSwapper2.approveMax(token, spender, amount);
            }
            //call the target
            (bool success, bytes memory returnData) = target.call{value: request.calls[i].nativeValueToSend}(request.calls[i].data);
            if (!success) {
                revert(LibSwapper2._getRevertMsg(returnData));
            }
            unchecked {
                ++i;
            }
        }
    }

    function overwriteAmount(uint256 _amount, GenericBridgeRequest memory _request) internal pure {
        for (uint256 i; i < _request.calls.length;) {
            if (_request.calls[i].startIndexForAmount > 0) {
                // skip if 0
                bytes memory data = _request.calls[i].data;
                uint256 index = _request.calls[i].startIndexForAmount;
                if (index < 4 || data.length < 32 || index > (data.length - 32)) {
                    revert GenericBridge__InvalidStartIndex();
                }
                _amount = _request.extraERC20Fee > 0 
                    ? _amount + uint256(_request.extraERC20Fee)
                    : _amount - uint256(-(_request.extraERC20Fee));

                assembly {
                    mstore(add(data, add(index, 32)), _amount)
                }
            }
            if (_request.calls[i].valueIsBridgeAmount == true) {
                _request.calls[i].nativeValueToSend = _amount + _request.extraFee;
            }
            unchecked {
                ++i;
            }
        }
    }
}
