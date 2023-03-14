// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "./Interchain.sol";
import "../libraries/LibSwapper.sol";

/// @title An interface to RangoVoyager.sol contract to improve type hinting
/// @author Uchiha Sasuke
interface IRangoVoyager {
    /// @notice The request object for Voyager bridge call
    struct VoyagerBridgeRequest {
        uint8 voyagerDestinationChainId;
        bytes32 resourceID;
        address feeTokenAddress;
        uint256 dstTokenAmount;
        uint256 feeAmount;
        bytes data;
    }

    function voyagerSwapAndBridge(
        LibSwapper.SwapRequest memory request,
        LibSwapper.Call[] calldata calls,
        IRangoVoyager.VoyagerBridgeRequest memory bridgeRequest
    ) external payable;

    function voyagerBridge(
        IRangoVoyager.VoyagerBridgeRequest memory request,
        IRango.RangoBridgeRequest memory bridgeRequest
    ) external payable;
}