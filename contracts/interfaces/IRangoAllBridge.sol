// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import "../libraries/LibSwapper.sol";
import "./IRango.sol";
import "./IAllBridgeRouter.sol";

/// @title An interface to
/// @author George
interface IRangoAllBridge {
    /// @notice The request object for AllBridge
    /// @param recipient Address to receive funds at on destination chain.
    /// @param destinationChainId the chain id of destination (this is specific chain id for allbridge, not general evm chain id)
    /// @param receiveTokenAddress token address to be received in destination.
    /// @param nonce
    /// @param messenger The underlying bridge protocol
    /// @param transferFee The native amount of tokens for bridging fee
    struct AllBridgeRequest {
        bytes32 recipient;
        uint destinationChainId;
        bytes32 receiveTokenAddress;
        uint256 nonce;
        IAllBridgeRouter.MessengerProtocol messenger;
        uint transferFee;
        uint feeTokenAmount;
    }

    function allbridgeSwapAndBridge(
        LibSwapper.SwapRequest memory request,
        LibSwapper.Call[] calldata calls,
        AllBridgeRequest memory bridgeRequest
    ) external payable;

    function allbridgeBridge(
        AllBridgeRequest memory request,
        IRango.RangoBridgeRequest memory bridgeRequest
    ) external payable;
}