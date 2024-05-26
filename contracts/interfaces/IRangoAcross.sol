// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import "../libraries/LibSwapper.sol";
import "./IRango.sol";

/// @title An interface to RangoAcross.sol contract to improve type hinting
/// @author George
interface IRangoAcross {
    /// @notice The request object for Across bridge call
    /// @param spokePoolAddress The address of Across spoke pool that deposit should be done to
    /// @param depositor The account credited with the deposit who can request to "speed up" this deposit by modifying the output amount, recipient, and message.
    /// @param exclusiveRelayer This is the exclusive relayer who can fill the deposit before the exclusivity deadline.
    /// @param outputToken Token that is received on destination chain by recipient.
    /// @param fillDeadline The timestamp on the destination chain after which this deposit can no longer be filled.
    /// @param exclusivityDeadline The timestamp on the destination chain after which any relayer can fill the deposit.
    /// @param recipient Address to receive funds at on destination chain.
    /// @param originToken Token to lock into this contract to initiate deposit. Can be address(0)
    /// @param destinationChainId Denotes network where user will receive funds from SpokePool by a relayer.
    /// @param totalRelayFeeAmount The amount of tokens that should be paid to the relayer as fee.
    /// @param quoteTimestamp Timestamp used by relayers to compute this deposit's realizedLPFeePct which is paid to LP pool on HubPool.
    /// @param message message that will be passed to destination chain. Can be empty.
    struct AcrossBridgeRequest {
        address spokePoolAddress;
        address depositor;
        address exclusiveRelayer;
        address outputToken;
        uint32 fillDeadline;
        uint32 exclusivityDeadline;
        address recipient;
        uint256 destinationChainId;
        uint256 totalRelayFeeAmount;
        uint32 quoteTimestamp;
        bytes message;
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