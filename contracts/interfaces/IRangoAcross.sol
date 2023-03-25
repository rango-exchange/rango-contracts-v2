// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.16;

import "../libraries/LibSwapper.sol";
import "./IRango.sol";

/// @title An interface to RangoAcross.sol contract to improve type hinting
/// @author Uchiha Sasuke
interface IRangoAcross {
    /// @notice The request object for Across bridge call
    /// @param spokePoolAddress The address of Across spoke pool that deposit should be done to
    /// @param recipient Address to receive funds at on destination chain.
    /// @param originToken Token to lock into this contract to initiate deposit. Can be address(0)
    /// @param destinationChainId Denotes network where user will receive funds from SpokePool by a relayer.
    /// @param relayerFeePct % of deposit amount taken out to incentivize a fast relayer.
    /// @param quoteTimestamp Timestamp used by relayers to compute this deposit's realizedLPFeePct which is paid to LP pool on HubPool.
    struct AcrossBridgeRequest {
        address spokePoolAddress;
        address recipient;
        uint256 destinationChainId;
        uint64 relayerFeePct;
        uint32 quoteTimestamp;
    }

    function acrossSwapAndBridge(
        LibSwapper.SwapRequest memory request,
        LibSwapper.Call[] calldata calls,
        AcrossBridgeRequest memory bridgeRequest
    ) external payable;

    function acrossBridge(
        AcrossBridgeRequest memory request,
        IRango.RangoBridgeRequest memory bridgeRequest
    ) external payable;
}