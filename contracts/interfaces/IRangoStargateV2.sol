// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import "./IStargateV2.sol";
import "./Interchain.sol";
import "./IRango.sol";
import "../libraries/LibSwapper.sol";

/// @title An interface to interact with RangoStargateV2Facet
/// @author George
interface IRangoStargateV2 {

    struct StargateV2Request {
        address poolContract;
        uint32 dstEid;
        uint16 dstChainId;
        bytes32 recipientAddress;
        uint256 minAmountLD;
        address refundAddress;
        uint256 nativeFee;

        bytes extraOptions; // Additional options supplied by the caller to be used in the LayerZero message.
        bytes composeMsg; // The composed message for the send() operation.
        bytes oftCmd; // The OFT command to be executed, unused in default OFT implementations.
    }

    function stargateV2SwapAndBridge(
        LibSwapper.SwapRequest memory request,
        LibSwapper.Call[] calldata calls,
        IRangoStargateV2.StargateV2Request memory stargateV2Request
    ) external payable;

    function stargateV2Bridge(
        IRangoStargateV2.StargateV2Request memory stargateV2Request,
        IRango.RangoBridgeRequest memory bridgeRequest
    ) external payable;
}
