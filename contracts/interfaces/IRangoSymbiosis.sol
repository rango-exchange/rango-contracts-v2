// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.16;

import "./Interchain.sol";
import "../libraries/LibSwapper.sol";

interface IRangoSymbiosis {

    struct SymbiosisBridgeRequest {
        SymbiosisBridgeType bridgeType;
        MetaRouteTransaction metaRouteTransaction;
        address receiver;
        uint256 toChainId;
    }

    enum SymbiosisBridgeType {META_BURN, META_SYNTHESIZE}

    struct MetaRouteTransaction {
        bytes firstSwapCalldata;
        bytes secondSwapCalldata;
        address[] approvedTokens;
        address firstDexRouter;
        address secondDexRouter;
        uint256 amount;
        bool nativeIn;
        address relayRecipient;
        bytes otherSideCalldata;
    }

    struct SwapData {
        bytes poolData;
        address poolAddress;
    }

    struct BridgeData {
        address oppositeBridge;
        uint256 chainID;
        bytes32 clientID;
    }

    struct UserData {
        address receiveSide;
        address revertableAddress;
        address token;
        address syntCaller;
    }

    struct OtherSideData {
        uint256 stableBridgingFee;
        uint256 amount;
        address chain2address;
        address[] swapTokens;
        address finalReceiveSide;
        address finalToken;
        uint256 finalAmount;
    }

    struct MetaBurnTransaction {
        uint256 stableBridgingFee;
        uint256 amount;
        address syntCaller;
        address finalReceiveSide;
        address sToken;
        bytes finalCallData;
        uint256 finalOffset;
        address chain2address;
        address receiveSide;
        address oppositeBridge;
        address revertableAddress;
        uint256 chainID;
        bytes32 clientID;
    }

    struct MetaSynthesizeTransaction {
        uint256 stableBridgingFee;
        uint256 amount;
        address rToken;
        address chain2address;
        address receiveSide;
        address oppositeBridge;
        address syntCaller;
        uint256 chainID;
        address[] swapTokens;
        address secondDexRouter;
        bytes secondSwapCalldata;
        address finalReceiveSide;
        bytes finalCalldata;
        uint256 finalOffset;
        address revertableAddress;
        bytes32 clientID;
    }

    function symbiosisSwapAndBridge(
        LibSwapper.SwapRequest memory request,
        LibSwapper.Call[] calldata calls,
        IRangoSymbiosis.SymbiosisBridgeRequest memory bridgeRequest
    ) external payable;

    function symbiosisBridge(
        IRangoSymbiosis.SymbiosisBridgeRequest memory symbiosisRequest,
        IRango.RangoBridgeRequest memory bridgeRequest
    ) external payable;

}
