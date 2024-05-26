// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.16;

// This interface is expected to be implemented by any contract that expects to receive messages from the nitro asset forwarder.
interface NitroAssetForwarderMessageHandler {
    function handleMessage(
        address tokenSent,
        uint256 amount,
        bytes memory message
    ) external payable;
}