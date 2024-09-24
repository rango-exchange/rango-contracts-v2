// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import "../libraries/LibSwapper.sol";
import "./IRango.sol";

/// @title An interface to RangoChainFlipFacet.sol contract to improve type hinting
/// @author Smnp
interface IRangoChainFlip {
    /// @notice The request object for ChainFlip bridge call
    /// @param dstChain Destination chain for the swap.
    /// @param dstAddress Address where the swapped tokens will be sent to on the destination chain. Addresses must be encoded into a bytes type.
    /// @param dstToken Token to be received on the destination chain.
    /// @param message Message that is passed to the destination address on the destination. It must be shorter than 10k bytes.
    /// @param gasAmount Gas budget for the call on the destination chain. This amount is based on the source asset and will be subtracted from the input amount and swapped to pay for gas.
    /// @param cfParameters Additional metadata for future features. Currently unused.
    struct ChainFlipBridgeRequest {
        uint32 dstChain;
        bytes dstAddress;
        uint32 dstToken;
        bytes message;
        uint256 gasAmount;
        bytes cfParameters;
    }

    function chainFlipSwapAndBridge(
        LibSwapper.SwapRequest memory request,
        LibSwapper.Call[] calldata calls,
        ChainFlipBridgeRequest memory bridgeRequest
    ) external payable;

    function chainFlipBridge(
        ChainFlipBridgeRequest memory request,
        IRango.RangoBridgeRequest memory bridgeRequest
    ) external payable;
}