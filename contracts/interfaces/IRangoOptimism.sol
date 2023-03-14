// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "./Interchain.sol";
import "../libraries/LibSwapper.sol";
import "./IRango.sol";

/// @title IRangoOptimism
/// @author AMA
interface IRangoOptimism {
    /// @notice The request object for Optimism bridge call
    struct OptimismBridgeRequest {
        address receiver;
        address l2TokenAddress;
        uint32 l2Gas;
        bool isSynth;
    }

    function optimismBridge(
        IRangoOptimism.OptimismBridgeRequest memory request,
        IRango.RangoBridgeRequest memory bridgeRequest
    ) external payable;

    function optimismSwapAndBridge(
        LibSwapper.SwapRequest memory request,
        LibSwapper.Call[] calldata calls,
        IRangoOptimism.OptimismBridgeRequest memory bridgeRequest
    ) external payable;
}