// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import "./Interchain.sol";
import "./IRango.sol";
import "../libraries/LibSwapper.sol";


/// @title An interface to RangoConnext.sol contract to improve type hinting
/// @author jeoffery
interface IRangoConnext {

    enum ConnextBridgeType {TRANSFER, TRANSFER_WITH_MESSAGE}

    /// @dev symbol is case sensitive
    /// @param bridgeType to distinguish between simple bridge and bridge with message
    /// @param receiver The receiver address in the destination chain
    /// @param delegateAddress will be able to do some controlling tasks e.g. increase slippage rate, if tx is stuck
    /// @param toChainId The network id of destination chain, ex: 56 for BSC
    /// @param relayerFee fee of the transaction collected by connext
    /// @param destinationDomain unique domain id for each network used by connext
    /// @param slippage maximum tolerance slippage rate
    /// @param feeInNative if false, fee will be charged using token that is being bridged
    /// @param imMessage encoded message to be used in destination
    struct ConnextBridgeRequest {
        ConnextBridgeType bridgeType;
        address receiver;
        address delegateAddress;
        uint256 toChainId;
        uint256 relayerFee;
        uint32 destinationDomain;
        uint256 slippage;
        bool feeInNative;
        bytes imMessage;
    }

    function connextSwapAndBridge(
        LibSwapper.SwapRequest memory request,
        LibSwapper.Call[] calldata calls,
        IRangoConnext.ConnextBridgeRequest memory bridgeRequest
    ) external payable;

    function connextBridge(
        ConnextBridgeRequest memory request,
        IRango.RangoBridgeRequest memory bridgeRequest
    ) external payable;
}