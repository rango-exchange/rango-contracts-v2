// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

/// @title An interface to interchain message types
/// @author Uchiha Sasuke
interface Interchain {
    enum ActionType { NO_ACTION, UNI_V2, UNI_V3, CALL, CURVE }
    enum CallSubActionType { WRAP, UNWRAP, NO_ACTION }

    struct RangoInterChainMessage {
        address requestId;
        uint64 dstChainId;
        // @dev bridgeRealOutput is only used to disambiguate receipt of WETH and ETH and SHOULD NOT be used anywhere else!
        address bridgeRealOutput;
        address toToken;
        address originalSender;
        address recipient;
        ActionType actionType;
        bytes action;
        CallSubActionType postAction;
        uint16 dAppTag;

        // Extra message
        bytes dAppMessage;
        address dAppSourceContract;
        address dAppDestContract;
    }

    struct UniswapV2Action {
        address dexAddress;
        uint amountOutMin;
        address[] path;
        uint deadline;
    }

    struct UniswapV3ActionExactInputParams {
        address dexAddress;
        address tokenIn;
        address tokenOut;
        bytes encodedPath;
        uint256 deadline;
        uint256 amountOutMinimum;
    }

    /// @notice The requested call data which is computed off-chain and passed to the contract
    /// @param target The dex contract address that should be called
    /// @param overwriteAmount if true, by using startIndexForAmount actual value will be used for swap
    /// @param startIndexForAmount if overwriteAmount is false, this parameter will be ignored. must be byte number
    /// @param callData The required data field that should be give to the dex contract to perform swap
    struct CallAction {
        address tokenIn;
        address spender;
        CallSubActionType preAction;
        address payable target;
        bool overwriteAmount;
        uint256 startIndexForAmount;
        bytes callData;
    }

    /// @notice the data needed to call `exchange` method for swap via Curve
    struct CurveAction {
        address routerContractAddress;
        address [11] routes;
        uint256 [5][5] swap_params;
        uint256 expected;
        address [5] pools;
        address toToken;
    }

}