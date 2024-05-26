// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import "../libraries/LibSwapper.sol";
import "./IRango.sol";

/// @title An interface to RangoHyphen.sol contract to improve type hinting
/// @author Hellboy
interface IRangoHyphen {

    /// @param receiver The receiver address in the destination chain
    /// @param toChainId The network id of destination chain, ex: 56 for BSC
    struct HyphenBridgeRequest {
        address receiver;
        uint256 toChainId;
    }

    function hyphenSwapAndBridge(
        LibSwapper.SwapRequest memory request,
        LibSwapper.Call[] calldata calls,
        IRangoHyphen.HyphenBridgeRequest memory bridgeRequest
    ) external payable;

    function hyphenBridge(
        IRangoHyphen.HyphenBridgeRequest memory request,
        IRango.RangoBridgeRequest memory bridgeRequest
    ) external payable;
}