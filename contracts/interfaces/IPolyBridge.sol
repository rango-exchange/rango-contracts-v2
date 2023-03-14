// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

interface IPolyBridge {
    function lock(
        address fromAsset,
        uint64 toChainId,
        bytes memory toAddress,
        uint amount,
        uint fee,
        uint id
    ) external payable;
}