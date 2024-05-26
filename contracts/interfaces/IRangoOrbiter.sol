// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import "../libraries/LibSwapper.sol";
import "./IRango.sol";

/// @title An interface to Rango Orbiter Facet contract to improve type hinting
/// @author George
interface IRangoOrbiter {
    /// @notice The request object for Orbiter bridge call
    /// @param routerContract The address of Orbiter router contract
    /// @param recipient The address of destination wallet to receive funds
    /// @param data The bytes data to be passed to orbiter router
    struct OrbiterBridgeRequest {
        address routerContract;
        address recipient;
        bytes data;
    }

    function orbiterSwapAndBridge(
        LibSwapper.SwapRequest memory request,
        LibSwapper.Call[] calldata calls,
        OrbiterBridgeRequest memory bridgeRequest
    ) external payable;

    function orbiterBridge(
        OrbiterBridgeRequest memory request,
        IRango.RangoBridgeRequest memory bridgeRequest
    ) external payable;
}