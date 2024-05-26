// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.25;

// This interface is expected to be implemented by any contract that expects to recieve messages from the SpokePool.
interface AcrossMessageHandler {
    function handleV3AcrossMessage(
        address tokenSent,
        uint256 amount,
        address relayer,
        bytes memory message
    ) external;
}