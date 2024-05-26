// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

/// @title The root contract that handles Rango's interaction with Swft bridge
/// @author George
abstract contract ISwft {
    function swap(
        address fromToken,
        string memory toToken,
        string memory destination,
        uint256 fromAmount,
        uint256 minReturnAmount
    ) external virtual;

    function swapEth(
        string memory toToken,
        string memory destination,
        uint256 minReturnAmount
    ) external virtual payable;
}