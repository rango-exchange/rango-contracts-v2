// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import "../libraries/LibSwapper.sol";
import "./IRango.sol";

/// @title An interface to RangoSwftFacet contract to improve type hinting
/// @author George
interface IRangoSwft {
    /// @notice The request object for Swft bridge call
    /// @param toToken destination token
    /// @param destination destination address
    /// @param minReturnAmount the minimum output amount
    struct SwftBridgeRequest {
        string toToken;
        string destination;
        uint256 minReturnAmount;
    }

    function swftSwapAndBridge(
        LibSwapper.SwapRequest memory request,
        LibSwapper.Call[] calldata calls,
        SwftBridgeRequest memory bridgeRequest
    ) external payable;

    function swftBridge(
        SwftBridgeRequest memory request,
        IRango.RangoBridgeRequest memory bridgeRequest
    ) external payable;
}