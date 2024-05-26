// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import "./Interchain.sol";
import "./IRango.sol";
import "../libraries/LibSwapper.sol";
import "../utils/DlnOrderData.sol";


/// @title An interface to RangoDeBrdigeFacet.sol contract to improve type hinting
/// @author jeoffery
interface IRangoDeBridge {

    enum DeBridgeBridgeType {TRANSFER, TRANSFER_WITH_MESSAGE}

    struct DeBridgeRequest {
        OrderCreation orderCreation;
        uint64 salt;
        uint32 referralCode;
        bytes affiliateFee;
        bytes permitEnvelope;
        bytes metadata;
        uint protocolFee;
        DeBridgeBridgeType bridgeType;
        bool hasDestSwap;
    }

    function deBridgeSwapAndBridge(
        LibSwapper.SwapRequest memory request,
        LibSwapper.Call[] calldata calls,
        DeBridgeRequest memory bridgeRequest
    ) external payable;

    function deBridgeBridge(
        DeBridgeRequest memory request,
        IRango.RangoBridgeRequest memory bridgeRequest
    ) external payable;
}