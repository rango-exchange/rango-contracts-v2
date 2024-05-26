// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25; 

import "./Interchain.sol";
import "../libraries/LibSwapper.sol";

/// @title An interface to RangoNitroAssetForwarder.sol contract to improve type hinting
/// @author Shivam Agrawal
interface IRangoNitroAssetForwarder {
    /// @notice The request object for Voyager bridge call
    struct NitroBridgeRequest {
        uint256 partnerId;
        uint256 destAmount;
        address refundRecipient;
        bytes32 destChainId;
        bytes destToken;
        bytes recipient;
        bytes message;
    }

    function nitroAssetForwarderSwapAndBridge(
        LibSwapper.SwapRequest memory request,
        LibSwapper.Call[] calldata calls,
        NitroBridgeRequest memory bridgeRequest
    ) external payable;

    function nitroAssetForwarderBridge(
        NitroBridgeRequest memory request,
        IRango.RangoBridgeRequest memory bridgeRequest
    ) external payable;
}