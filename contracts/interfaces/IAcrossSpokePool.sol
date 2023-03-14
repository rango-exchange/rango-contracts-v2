// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

/// @title The root contract that handles Rango's interaction with Across bridge
/// @author Uchiha Sasuke
interface IAcrossSpokePool {
    function deposit(
        address recipient,
        address originToken,
        uint256 amount,
        uint256 destinationChainId,
        uint64 relayerFeePct,
        uint32 quoteTimestamp
    ) external payable;
}