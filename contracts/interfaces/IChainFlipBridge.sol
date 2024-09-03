// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.25;

// This interface is expected to be implemented by any contract that expects to recieve messages from the SpokePool.
interface IChainFlipBridge {
    // Swap native token
    function xSwapNative(
        uint32 dstChain,
        bytes calldata dstAddress,
        uint32 dstToken,
        bytes calldata cfParameters
    ) external payable;
 
    // Swap ERC20 token
    function xSwapToken(
        uint32 dstChain,
        bytes calldata dstAddress,
        uint32 dstToken,
        address srcToken, /// sep: change to address from IERC20
        uint256 amount,
        bytes calldata cfParameters
    ) external;

    // Swap native token with message
    function xCallNative(
        uint32 dstChain,
        bytes calldata dstAddress,
        uint32 dstToken,
        bytes calldata message,
        uint256 gasAmount,
        bytes calldata cfParameters
    ) external payable;
 
    // Swap ERC20 token with message
    function xCallToken(
        uint32 dstChain,
        bytes calldata dstAddress,
        uint32 dstToken,
        bytes calldata message,
        uint256 gasAmount,
        address srcToken, /// sep: change to address from IERC20
        uint256 amount,
        bytes calldata cfParameters
    ) external;
}