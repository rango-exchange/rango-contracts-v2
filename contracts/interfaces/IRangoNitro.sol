// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.16;

import "./Interchain.sol";
import "../libraries/LibSwapper.sol";

/// @title An interface to RangoVoyager.sol contract to improve type hinting
/// @author Uchiha Sasuke
interface IRangoNitro {
    /// @notice The request object for Voyager bridge call
    struct NitroBridgeRequest {
        uint256 partnerId;
        uint256 destAmount;
        address refundRecipient;
        string destChainId;
        bytes destToken;
        bytes recipient;
    }

    function nitroSwapAndBridge(
        LibSwapper.SwapRequest memory request,
        LibSwapper.Call[] calldata calls,
        NitroBridgeRequest memory bridgeRequest
    ) external payable;

    function nitroBridge(
        NitroBridgeRequest memory request,
        IRango.RangoBridgeRequest memory bridgeRequest
    ) external payable;
}
