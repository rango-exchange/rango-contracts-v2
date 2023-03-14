// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "../libraries/LibSwapper.sol";
import "./IRango.sol";

/// @title An interface to RangoPoly.sol contract to improve type hinting
/// @author AMA
interface IRangoPoly {

    /// @param receiver The receiver address in the destination chain
    /// @param toChainId The network id of destination chain, ex: 56 for BSC
    struct PolyBridgeRequest {
        address receiver;
        uint64 toChainId;
        uint256 fee;
        uint256 id;
    }

    function polyBridge(
        IRangoPoly.PolyBridgeRequest memory request,
        IRango.RangoBridgeRequest memory bridgeRequest
    ) external payable;

    function polySwapAndBridge(
        LibSwapper.SwapRequest memory request,
        LibSwapper.Call[] calldata calls,
        IRangoPoly.PolyBridgeRequest memory bridgeRequest
    ) external payable;
}