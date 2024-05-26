// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import "./Interchain.sol";
import "./IRango.sol";
import "../libraries/LibSwapper.sol";

/// @title The interface for interacting with arbitrum bridge delayed inbox
/// @author AMA
interface IRangoArbitrum {
    /// @notice The request object for Arbitrum bridge call
    struct ArbitrumBridgeRequest {
        address receiver;
        uint256 cost;
        uint256 maxGas;
        uint256 maxGasPrice;
        uint256 maxSubmissionCost;
    }

    function arbitrumBridge(
        IRangoArbitrum.ArbitrumBridgeRequest memory request,
        IRango.RangoBridgeRequest memory bridgeRequest
    ) external payable;

    function arbitrumSwapAndBridge(
        LibSwapper.SwapRequest memory request,
        LibSwapper.Call[] calldata calls,
        IRangoArbitrum.ArbitrumBridgeRequest memory bridgeRequest
    ) external payable;
}