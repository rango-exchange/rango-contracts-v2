// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.25;

// This interface is expected to be implemented by any contract that expects to recieve messages from the ChainFlip.
interface IChainFlipMessageHandler {
    function cfReceive(
        uint32 srcChain,
        bytes calldata srcAddress,
        bytes calldata message,
        address token,
        uint256 amount
    ) external payable;
}
