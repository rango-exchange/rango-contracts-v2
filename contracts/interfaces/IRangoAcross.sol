// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.16;

import "../libraries/LibSwapper.sol";
import "./IRango.sol";

/// @title An interface to RangoAcross.sol contract to improve type hinting
/// @author George
interface IRangoAcross {
    /// @notice The request object for Across bridge call
    /// @param spokePoolAddress The address of Across spoke pool that deposit should be done to
    /// @param recipient Address to receive funds at on destination chain.
    /// @param originToken Token to lock into this contract to initiate deposit. Can be address(0)
    /// @param destinationChainId Denotes network where user will receive funds from SpokePool by a relayer.
    /// @param relayerFeePct % of deposit amount taken out to incentivize a fast relayer.
    /// @param quoteTimestamp Timestamp used by relayers to compute this deposit's realizedLPFeePct which is paid to LP pool on HubPool.
    /// @param message message that will be passed to destination chain. Can be empty.
    /// @param maxCount used as a form of front-running protection. If we pass maxCount of 90 and when the tx is submitted the spoke has count of 100, the tx will revert. Default can be set to type(uint).max
    struct AcrossBridgeRequest {
        address spokePoolAddress;
        address recipient;
        uint256 destinationChainId;
        int64 relayerFeePct;
        uint32 quoteTimestamp;
        bytes message;
        uint256 maxCount;
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