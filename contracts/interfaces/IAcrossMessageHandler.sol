// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.16;

// This interface is expected to be implemented by any contract that expects to recieve messages from the SpokePool.
interface AcrossMessageHandler {
    function handleAcrossMessage(
        address tokenSent,
        uint256 amount,
        bytes memory message
    ) external payable;
}