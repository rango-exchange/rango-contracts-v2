// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "../libraries/LibSwapper.sol";
import "./IRango.sol";

/// @title Interface to interact with RangoThorchain contract.
/// @author Thinking Particle
interface IRangoThorchain {

    function thorchainSwapAndBridge(
        LibSwapper.SwapRequest memory request,
        LibSwapper.Call[] calldata calls,

        address tcRouter,
        address tcVault,
        string calldata thorchainMemo,
        uint expiration
    ) external payable;

    function thorchainBridge(
        IRango.RangoBridgeRequest memory request,
        address tcRouter,
        address tcVault,
        string calldata thorchainMemo,
        uint expiration
    ) external payable;

}