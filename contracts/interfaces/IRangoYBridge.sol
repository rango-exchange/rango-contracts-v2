// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import "./Interchain.sol";
import "./IRango.sol";
import "../libraries/LibSwapper.sol";


/// @title An interface to RangoYBridgeFacet.sol contract to improve type hinting
/// @author jeoffery
interface IRangoYBridge {

    /// @dev struct for yBridge information by facet
    /// @param receiver The receiver address in the destination chain
    /// @param toChainId The network id of destination chain, ex: 56 for BSC
    /// @param dstToken token address in destination chain
    /// @param referrer referrer address
    /// @param slippage slippage rate (only used if there is a swap on destination)
    /// @param expectedDstChainTokenAmount expected amount of tokens (this should be in the output token decimals)
    struct YBridgeRequest {
        address receiver;
        uint32 toChainId;
        address dstToken;
        address referrer;
        uint32 slippage;
        uint256 expectedDstChainTokenAmount;
    }

    function yBridgeSwapAndBridge(
        LibSwapper.SwapRequest memory request,
        LibSwapper.Call[] calldata calls,
        YBridgeRequest memory bridgeRequest
    ) external payable;

    function yBridgeBridge(
        YBridgeRequest memory request,
        IRango.RangoBridgeRequest memory bridgeRequest
    ) external payable;
}