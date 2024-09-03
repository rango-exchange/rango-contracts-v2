// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IUniswapV2.sol";
import "../interfaces/IUniswapV3.sol";
import "../interfaces/ICurve.sol";
import "../interfaces/IWETH.sol";
import "../interfaces/Interchain.sol";
import "../interfaces/IRangoMessageReceiver.sol";
import "../interfaces/IRangoMiddlewareWhitelists.sol";
import "./LibSwapper.sol";

library LibInterchain {
    /// Storage ///
    bytes32 internal constant LIBINTERCHAIN_CONTRACT_NAMESPACE = keccak256("exchange.rango.library.interchain");

    struct BaseInterchainStorage {
        address whitelistsStorageContract;
    }

    /// @notice This event indicates that a dApp used Rango messaging (dAppMessage field) and we delivered the message to it
    /// @param _receiverContract The address of dApp's contract that was called
    /// @param _token The address of the token that is sent to the dApp, ETH for native token
    /// @param _amount The amount of the token sent to them
    /// @param _status The status of operation, informing the dApp that the whole process was a success or refund
    /// @param _appMessage The custom message that the dApp asked Rango to deliver
    /// @param success Indicates that the function call to the dApp encountered error or not
    /// @param failReason If success = false, failReason will be the string reason of the failure (aka message of require)
    event CrossChainMessageCalled(
        address _receiverContract,
        address _token,
        uint _amount,
        IRangoMessageReceiver.ProcessStatus _status,
        bytes _appMessage,
        bool success,
        string failReason
    );

    event ActionDone(Interchain.ActionType actionType, address contractAddress, bool success, string reason);
    event SubActionDone(Interchain.CallSubActionType subActionType, address contractAddress, bool success, string reason);
    event WhitelistStorageAddressUpdated(address _oldAddress, address _newAddress);

    /// @notice is used to check if a contract is whitelisted or not
    /// @param _contractAddress the address of the contract to be checked
    /// @return true if contract is whitelisted
    function isContractWhitelisted(address _contractAddress) internal view returns(bool) {
        address whitelistsContractAddress = getLibInterchainStorage().whitelistsStorageContract;
        return IRangoMiddlewareWhitelists(whitelistsContractAddress).isContractWhitelisted(_contractAddress);
    }

    /// @notice is used to check if a DApp is whitelisted or not
    /// @param _messagingContract the address of the DApp to be checked
    /// @return true if DApp is whitelisted
    function isMessagingContractWhitelisted(address _messagingContract) internal view returns(bool) {
        address s = getLibInterchainStorage().whitelistsStorageContract;
        return IRangoMiddlewareWhitelists(s).isMessagingContractWhitelisted(_messagingContract);
    }

    /// @notice updates the address of whitelists storage
    /// @param _storageContract new address
    function updateWhitelistsContractAddress(address _storageContract) internal {
        require(_storageContract != address(0), "Invalid storage contract address");
        BaseInterchainStorage storage baseStorage = getLibInterchainStorage();
        address oldAddress = baseStorage.whitelistsStorageContract;
        baseStorage.whitelistsStorageContract = _storageContract;
        emit WhitelistStorageAddressUpdated(oldAddress, _storageContract);
    }

    function handleDestinationMessage(
        address _token,
        uint _amount,
        Interchain.RangoInterChainMessage memory m
    ) internal returns (address, uint256 dstAmount, IRango.CrossChainOperationStatus status) {
        address sourceToken = m.bridgeRealOutput == LibSwapper.ETH && _token == getWeth() ? LibSwapper.ETH : _token;

        bool ok = true;
        address receivedToken = sourceToken;
        dstAmount = _amount;

        if (m.actionType == Interchain.ActionType.UNI_V2)
            (ok, dstAmount, receivedToken) = _handleUniswapV2(sourceToken, _amount, m);
        else if (m.actionType == Interchain.ActionType.UNI_V3)
            (ok, dstAmount, receivedToken) = _handleUniswapV3(sourceToken, _amount, m);
        else if (m.actionType == Interchain.ActionType.CALL)
            (ok, dstAmount, receivedToken) = _handleCall(sourceToken, _amount, m);
        else if (m.actionType == Interchain.ActionType.CURVE)
            (ok, dstAmount, receivedToken) = _handleCurve(sourceToken, _amount, m);
        else if (m.actionType != Interchain.ActionType.NO_ACTION)
            revert("Unsupported actionType");

        if (ok && m.postAction != Interchain.CallSubActionType.NO_ACTION) {
            (ok, dstAmount, receivedToken) = _handlePostAction(receivedToken, dstAmount, m.postAction);
        }

        status = ok ? IRango.CrossChainOperationStatus.Succeeded : IRango.CrossChainOperationStatus.RefundInDestination;
        IRangoMessageReceiver.ProcessStatus dAppStatus = ok
            ? IRangoMessageReceiver.ProcessStatus.SUCCESS
            : IRangoMessageReceiver.ProcessStatus.REFUND_IN_DESTINATION;

        _sendTokenWithDApp(receivedToken, dstAmount, m.recipient, m.dAppMessage, m.dAppDestContract, dAppStatus);

        return (receivedToken, dstAmount, status);
    }

    /// @notice Performs a uniswap-v2 operation
    /// @param _message The interchain message that contains the swap info
    /// @param _amount The amount of input token
    /// @return ok Indicates that the swap operation was success or fail
    /// @return amountOut If ok = true, amountOut is the output amount of the swap
    function _handleUniswapV2(
        address _token,
        uint _amount,
        Interchain.RangoInterChainMessage memory _message
    ) private returns (bool ok, uint256 amountOut, address outToken) {
        Interchain.UniswapV2Action memory action = abi.decode((_message.action), (Interchain.UniswapV2Action));
        address weth = getWeth();
        if (isContractWhitelisted(action.dexAddress) != true) {
            // "Dex address is not whitelisted"
            return (false, _amount, _token);
        }
        if (action.path.length < 2) {
            // "Invalid uniswap-V2 path"
            return (false, _amount, _token);
        }

        bool shouldDeposit = _token == LibSwapper.ETH && action.path[0] == weth;
        if (!shouldDeposit) {
            if (_token != action.path[0]) {
                // "bridged token must be the same as the first token in destination swap path"
                return (false, _amount, _token);
            }
        } else {
            IWETH(weth).deposit{value : _amount}();
        }

        LibSwapper.approve(action.path[0], action.dexAddress, _amount);

        address toToken = action.path[action.path.length - 1];
        uint toBalanceBefore = LibSwapper.getBalanceOf(toToken);

        try
            IUniswapV2(action.dexAddress).swapExactTokensForTokens(
                _amount,
                action.amountOutMin,
                action.path,
                address(this),
                action.deadline
            )
        returns (uint256[] memory) {
            emit ActionDone(Interchain.ActionType.UNI_V2, action.dexAddress, true, "");
            // Note: instead of using return amounts of swapExactTokensForTokens,
            //       we get the diff balance of before and after. This prevents errors for tokens with transfer fees
            uint toBalanceAfter = LibSwapper.getBalanceOf(toToken);
            SafeERC20.forceApprove(IERC20(action.path[0]), action.dexAddress, 0);
            return (true, toBalanceAfter - toBalanceBefore, toToken);
        } catch {
            emit ActionDone(Interchain.ActionType.UNI_V2, action.dexAddress, false, "Uniswap-V2 call failed");
            SafeERC20.forceApprove(IERC20(action.path[0]), action.dexAddress, 0);
            return (false, _amount, shouldDeposit ? weth : _token);
        }
    }

    /// @notice Performs a uniswap-v3 operation
    /// @param _message The interchain message that contains the swap info
    /// @param _amount The amount of input token
    /// @return ok Indicates that the swap operation was success or fail
    /// @return amountOut If ok = true, amountOut is the output amount of the swap
    function _handleUniswapV3(
        address _token,
        uint _amount,
        Interchain.RangoInterChainMessage memory _message
    ) private returns (bool, uint256, address) {
        Interchain.UniswapV3ActionExactInputParams memory action = abi
            .decode((_message.action), (Interchain.UniswapV3ActionExactInputParams));

        if (isContractWhitelisted(action.dexAddress) != true) {
            // "Dex address is not whitelisted"
            return (false, _amount, _token);
        }

        address weth = getWeth();
        bool shouldDeposit = _token == LibSwapper.ETH && action.tokenIn == weth;
        if (!shouldDeposit) {
            if (_token != action.tokenIn) {
                // "bridged token must be the same as the tokenIn in uniswapV3"
                return (false, _amount, _token);
            }
        } else {
            IWETH(weth).deposit{value : _amount}();
        }

        LibSwapper.approve(action.tokenIn, action.dexAddress, _amount);

        address toToken = action.tokenOut;
        uint toBalanceBefore = LibSwapper.getBalanceOf(toToken);

        if (action.isRouter2 == false) {
            try
                IUniswapV3(action.dexAddress).exactInput(IUniswapV3.ExactInputParams({
                    path : action.encodedPath,
                    recipient : address(this),
                    deadline : action.deadline,
                    amountIn : _amount,
                    amountOutMinimum : action.amountOutMinimum
                }))
            returns (uint) {
                emit ActionDone(Interchain.ActionType.UNI_V3, action.dexAddress, true, "");
                // Note: instead of using return amounts of exactInput,
                //       we get the diff balance of before and after. This prevents errors for tokens with transfer fees.
                uint toBalanceAfter = LibSwapper.getBalanceOf(toToken);
                SafeERC20.forceApprove(IERC20(action.tokenIn), action.dexAddress, 0);
                return (true, toBalanceAfter - toBalanceBefore, toToken);
            } catch {
                emit ActionDone(Interchain.ActionType.UNI_V3, action.dexAddress, false, "Uniswap-V3 call failed");
                SafeERC20.forceApprove(IERC20(action.tokenIn), action.dexAddress, 0);
                return (false, _amount, shouldDeposit ? weth : _token);
            }
        }
        else {
             try
                IUniswapV3(action.dexAddress).exactInput(IUniswapV3.ExactInputParamsRouter2({
                    path : action.encodedPath,
                    recipient : address(this),
                    amountIn : _amount,
                    amountOutMinimum : action.amountOutMinimum
                }))
            returns (uint) {
                emit ActionDone(Interchain.ActionType.UNI_V3, action.dexAddress, true, "");
                // Note: instead of using return amounts of exactInput,
                //       we get the diff balance of before and after. This prevents errors for tokens with transfer fees.
                uint toBalanceAfter = LibSwapper.getBalanceOf(toToken);
                SafeERC20.forceApprove(IERC20(action.tokenIn), action.dexAddress, 0);
                return (true, toBalanceAfter - toBalanceBefore, toToken);
            } catch {
                emit ActionDone(Interchain.ActionType.UNI_V3, action.dexAddress, false, "Uniswap-V3 call failed");
                SafeERC20.forceApprove(IERC20(action.tokenIn), action.dexAddress, 0);
                return (false, _amount, shouldDeposit ? weth : _token);
            }   
        }
    }

    /// @notice Performs a contract call operation
    /// @param _message The interchain message that contains the swap info
    /// @param _amount The amount of input token
    /// @return ok Indicates that the swap operation was success or fail
    /// @return amountOut If ok = true, amountOut is the output amount of the swap
    function _handleCall(
        address _token,
        uint _amount,
        Interchain.RangoInterChainMessage memory _message
    ) private returns (bool ok, uint256 amountOut, address outToken) {
        Interchain.CallAction memory action = abi.decode((_message.action), (Interchain.CallAction));

        if (isContractWhitelisted(action.target) != true) {
            // "Action.target is not whitelisted"
            return (false, _amount, _token);
        }
        if (isContractWhitelisted(action.spender) != true) {
            // "Action.spender is not whitelisted"
            return (false, _amount, _token);
        }

        address sourceToken = _token;

        if (action.preAction == Interchain.CallSubActionType.WRAP) {
            if (_token != LibSwapper.ETH) {
                // "Cannot wrap non-native"
                return (false, _amount, _token);
            }
            if (action.tokenIn != getWeth()) {
                // "action.tokenIn must be WETH"
                return (false, _amount, _token);
            }
            (ok, amountOut, sourceToken) = _handleWrap(_token, _amount);
        } else if (action.preAction == Interchain.CallSubActionType.UNWRAP) {
            if (_token != getWeth()) {
                // "Cannot unwrap non-WETH"
                return (false, _amount, _token);
            }
            if (action.tokenIn != LibSwapper.ETH) {
                // "action.tokenIn must be ETH"
                return (false, _amount, _token);
            }
            (ok, amountOut, sourceToken) = _handleUnwrap(_token, _amount);
        } else {
            ok = true;
            if (action.tokenIn != _token) {
                // "_message.tokenIn mismatch in call"
                return (false, _amount, _token);
            }
        }
        if (!ok)
            return (false, _amount, _token);

        if (sourceToken != LibSwapper.ETH)
            LibSwapper.approve(sourceToken, action.spender, _amount);

        uint value = sourceToken == LibSwapper.ETH ? _amount : 0;
        uint toBalanceBefore = LibSwapper.getBalanceOf(_message.toToken);

        if (action.overwriteAmount == true) {
            bytes memory data = action.callData;
            uint256 index = action.startIndexForAmount;
            // Avoid malicious overwriting of function sig or invalid location:
            if (index < 4 || index > (data.length - 32))
                return (false, _amount, _token);
            assembly {
                mstore(add(data, add(index,32)), _amount)
            }
        }

        (bool success, bytes memory ret) = action.target.call{value: value}(action.callData);

        if (sourceToken != LibSwapper.ETH)
            SafeERC20.forceApprove(IERC20(sourceToken), action.spender, 0);

        if (success) {
            emit ActionDone(Interchain.ActionType.CALL, action.target, true, "");
            uint toBalanceAfter = LibSwapper.getBalanceOf(_message.toToken);
            return (true, toBalanceAfter - toBalanceBefore, _message.toToken);
        } else {
            emit ActionDone(Interchain.ActionType.CALL, action.target, false, LibSwapper._getRevertMsg(ret));
            return (false, _amount, sourceToken);
        }
    }

    /// @notice Performs a swap operation using Curve fi
    /// @param _message The interchain message that contains the swap info
    /// @param _amount The amount of input token
    /// @return ok Indicates that the swap operation was success or fail
    /// @return amountOut If ok = true, amountOut is the output amount of the swap
    function _handleCurve(
        address _token,
        uint _amount,
        Interchain.RangoInterChainMessage memory _message
    ) private returns (bool ok, uint256 amountOut, address outToken) {
        Interchain.CurveAction memory action = abi.decode((_message.action), (Interchain.CurveAction));
        if (isContractWhitelisted(action.routerContractAddress) != true) {
            // "Dex address is not whitelisted"
            return (false, _amount, _token);
        }

        uint value = 0;
        if (_token == LibSwapper.ETH) {
            if (action.routes[0] != address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)) {
                return (false, _amount, _token);
            }
            value = _amount;
        } else {
            if (_token != action.routes[0]) {
                return (false, _amount, _token);
            }
            LibSwapper.approve(_token, action.routerContractAddress, _amount);
        }

        address toToken = action.toToken;
        uint toBalanceBefore = LibSwapper.getBalanceOf(toToken);

        try
            ICurve(action.routerContractAddress).exchange{value: value}(
                action.routes,
                action.swap_params,
                _amount,
                action.expected,
                action.pools,
                address(this)
            )
        returns (uint256) {
            emit ActionDone(Interchain.ActionType.CURVE, action.routerContractAddress, true, "");
            uint toBalanceAfter = LibSwapper.getBalanceOf(toToken);
            if (_token != LibSwapper.ETH) {
                SafeERC20.forceApprove(IERC20(_token), action.routerContractAddress, 0);
            }
            return (true, toBalanceAfter - toBalanceBefore, toToken);
        } catch {
            emit ActionDone(Interchain.ActionType.CURVE, action.routerContractAddress, false, "Curve call failed");
            if (_token != LibSwapper.ETH) {
                SafeERC20.forceApprove(IERC20(_token), action.routerContractAddress, 0);
            }
            return (false, _amount, _token);
        }
    }


    /// @notice Performs a post action operation
    /// @param _postAction The type of action to perform such as WRAP, UNWRAP
    /// @param _amount The amount of input token
    /// @return ok Indicates that the swap operation was success or fail
    /// @return amountOut If ok = true, amountOut is the output amount of the swap
    function _handlePostAction(
        address _token,
        uint _amount,
        Interchain.CallSubActionType _postAction
    ) private returns (bool ok, uint256 amountOut, address outToken) {

        if (_postAction == Interchain.CallSubActionType.WRAP) {
            if (_token != LibSwapper.ETH) {
                // "Cannot wrap non-native"
                return (false, _amount, _token);
            }
            (ok, amountOut, outToken) = _handleWrap(_token, _amount);
        } else if (_postAction == Interchain.CallSubActionType.UNWRAP) {
            if (_token != getWeth()) {
                // "Cannot unwrap non-WETH"
                return (false, _amount, _token);
            }
            (ok, amountOut, outToken) = _handleUnwrap(_token, _amount);
        } else {
            // revert("Unsupported post-action");
            return (false, _amount, _token);
        }
        if (!ok)
            return (false, _amount, _token);
        return (ok, amountOut, outToken);
    }

    /// @notice Performs a WETH.deposit operation
    /// @param _amount The amount of input token
    /// @return ok Indicates that the swap operation was success or fail
    /// @return amountOut If ok = true, amountOut is the output amount of the swap
    function _handleWrap(
        address _token,
        uint _amount
    ) private returns (bool ok, uint256 amountOut, address outToken) {
        if (_token != LibSwapper.ETH) {
            // "Cannot wrap non-ETH tokens"
            return (false, _amount, _token);
        }
        address weth = getWeth();
        IWETH(weth).deposit{value: _amount}();
        emit SubActionDone(Interchain.CallSubActionType.WRAP, weth, true, "");

        return (true, _amount, weth);
    }

    /// @notice Performs a WETH.deposit operation
    /// @param _amount The amount of input token
    /// @return ok Indicates that the swap operation was success or fail
    /// @return amountOut If ok = true, amountOut is the output amount of the swap
    function _handleUnwrap(
        address _token,
        uint _amount
    ) private returns (bool ok, uint256 amountOut, address outToken) {
        address weth = getWeth();
        if (_token != weth)
            // revert("Non-WETH tokens unwrapped");
            return (false, _amount, _token);

        IWETH(weth).withdraw(_amount);
        emit SubActionDone(Interchain.CallSubActionType.UNWRAP, weth, true, "");

        return (true, _amount, LibSwapper.ETH);
    }

    /// @notice An internal function to send a token from the current contract to another contract or wallet
    /// @dev This function also can convert WETH to ETH before sending if _withdraw flat is set to true
    /// @dev To send native token _nativeOut param should be set to true, otherwise we assume it's an ERC20 transfer
    /// @dev If there is a message from a dApp it sends the money to the contract instead of the end-user and calls its handleRangoMessage
    /// @param _token The token that is going to be sent to a wallet, ZERO address for native
    /// @param _amount The sent amount
    /// @param _receiver The receiver wallet address or contract
    function _sendTokenWithDApp(
        address _token,
        uint256 _amount,
        address _receiver,
        bytes memory _dAppMessage,
        address _dAppReceiverContract,
        IRangoMessageReceiver.ProcessStatus processStatus
    ) internal {
        bool thereIsAMessage = _dAppReceiverContract != LibSwapper.ETH;
        address immediateReceiver = thereIsAMessage ? _dAppReceiverContract : _receiver;
        emit LibSwapper.SendToken(_token, _amount, immediateReceiver);

        if (_token == LibSwapper.ETH) {
            LibSwapper._sendNative(immediateReceiver, _amount);
        } else {
            SafeERC20.safeTransfer(IERC20(_token), immediateReceiver, _amount);
        }

        if (thereIsAMessage) {
            require(
                isMessagingContractWhitelisted(_dAppReceiverContract),
                "3rd-party contract not whitelisted"
            );

            try IRangoMessageReceiver(_dAppReceiverContract)
                .handleRangoMessage(_token, _amount, processStatus, _dAppMessage)
            {
                emit CrossChainMessageCalled(_dAppReceiverContract, _token, _amount, processStatus, _dAppMessage, true, "");
            } catch Error(string memory reason) {
                emit CrossChainMessageCalled(_dAppReceiverContract, _token, _amount, processStatus, _dAppMessage, false, reason);
            } catch (bytes memory lowLevelData) {
                emit CrossChainMessageCalled(_dAppReceiverContract, _token, _amount, processStatus, _dAppMessage, false, LibSwapper._getRevertMsg(lowLevelData));
            }
        }
    }

        /// @notice get wrapped token address on the current chain from shared storage contract
    /// @return WETH address
    function getWeth() internal view returns(address) {
        address whitelistsContractAddress = getLibInterchainStorage().whitelistsStorageContract;
        return IRangoMiddlewareWhitelists(whitelistsContractAddress).getWeth();
    }

    /// @notice returns whether the middlewares are in paused state
    /// @return middlewaresPaused bool true if middlewares are paused. 
    function getMiddlewaresPaused() internal view returns (bool) {
        address whitelistsContractAddress = getLibInterchainStorage().whitelistsStorageContract;
        return IRangoMiddlewareWhitelists(whitelistsContractAddress).getMiddlewaresPaused();
    }

    /// @notice A utility function to fetch storage from a predefined random slot using assembly
    /// @return s The storage object
    function getLibInterchainStorage() internal pure returns (BaseInterchainStorage storage s) {
        bytes32 namespace = LIBINTERCHAIN_CONTRACT_NAMESPACE;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            s.slot := namespace
        }
    }
}