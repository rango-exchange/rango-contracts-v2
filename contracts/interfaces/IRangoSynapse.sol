// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.16;

import "../libraries/LibSwapper.sol";

/// @title An interface to RangoSynapse.sol contract to improve type hinting
/// @author Rango DeXter
interface IRangoSynapse {

    enum SynapseBridgeType {
        SWAP_AND_REDEEM,
        SWAP_ETH_AND_REDEEM,
        SWAP_AND_REDEEM_AND_SWAP,
        SWAP_AND_REDEEM_AND_REMOVE,
        REDEEM,
        REDEEM_AND_SWAP,
        REDEEM_AND_REMOVE,
        DEPOSIT,
        DEPOSIT_ETH,
        DEPOSIT_AND_SWAP,
        DEPOSIT_ETH_AND_SWAP,
        ZAP_AND_DEPOSIT,
        ZAP_AND_DEPOSIT_AND_SWAP
    }

    /// @notice The request object for Synapse bridge call
    struct SynapseBridgeRequest {
        SynapseBridgeType bridgeType;
        address router;
        address to;
        uint256 chainId;
        address bridgeToken;
        uint8 tokenIndexFrom;
        uint8 tokenIndexTo;
        uint256 minDy;
        uint256 deadline;
        uint8 swapTokenIndexFrom;
        uint8 swapTokenIndexTo;
        uint256 swapMinDy;
        uint256 swapDeadline;
        uint256[] liquidityAmounts;
    }

    event SynapseBridgeDetailEvent(
        address bridgeToken,
        uint8 tokenIndexFrom,
        uint8 tokenIndexTo,
        uint256 minDy,
        uint256 deadline,
        uint8 swapTokenIndexFrom,
        uint8 swapTokenIndexTo,
        uint256 swapMinDy,
        uint256 swapDeadline
    );

    function synapseSwapAndBridge(
        LibSwapper.SwapRequest memory request,
        LibSwapper.Call[] calldata calls,
        IRangoSynapse.SynapseBridgeRequest memory bridgeRequest
    ) external payable;

    function synapseBridge(
        IRangoSynapse.SynapseBridgeRequest memory request,
        IRango.RangoBridgeRequest memory bridgeRequest
    ) external payable;
}