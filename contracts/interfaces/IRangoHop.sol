// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.16;

import "../libraries/LibSwapper.sol";
import "./IRango.sol";

/// @title An interface to RangoHop.sol contract to improve type hinting
/// @author Uchiha Sasuke
interface IRangoHop {
    enum HopActionType { SWAP_AND_SEND, SEND_TO_L2 }

    struct HopRequest {
        HopActionType actionType;
        address bridgeAddress;
        uint256 chainId;
        address recipient;
        uint256 bonderFee;
        uint256 amountOutMin;
        uint256 deadline;
        uint256 destinationAmountOutMin;
        uint256 destinationDeadline;
        address relayer;
        uint256 relayerFee;
    }

    function hopBridge(
        IRangoHop.HopRequest memory request,
        IRango.RangoBridgeRequest memory bridgeRequest
    ) external payable;

    function hopSwapAndBridge(
        LibSwapper.SwapRequest memory request,
        LibSwapper.Call[] calldata calls,
        IRangoHop.HopRequest memory bridgeRequest
    ) external payable;
}