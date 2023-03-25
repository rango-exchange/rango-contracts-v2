// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.16;

import "../libraries/LibSwapper.sol";

/// @title An interface to RangoWormhole.sol contract to improve type hinting
/// @author AMA
interface IRangoWormhole {

    enum WormholeBridgeType { TRANSFER, TRANSFER_WITH_MESSAGE }

    struct WormholeBridgeRequest {
        WormholeBridgeType bridgeType;
        uint16 recipientChain;
        bytes32 recipient;
        uint256 fee;
        uint32 nonce;
 
        bytes imMessage;
    }

    function wormholeBridge(
        IRangoWormhole.WormholeBridgeRequest memory request,
        IRango.RangoBridgeRequest memory bridgeRequest
    ) external payable;

    function wormholeSwapAndBridge(
        LibSwapper.SwapRequest memory request,
        LibSwapper.Call[] calldata calls,
        IRangoWormhole.WormholeBridgeRequest memory bridgeRequest
    ) external payable;
}