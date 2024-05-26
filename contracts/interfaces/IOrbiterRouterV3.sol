// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

/// @title An interface to interact with Orbiter router contracts
/// @author George
interface IOrbiterRouterV3 {
    /**
    * @dev Transfer Ether to a specified address.
     * @param to The destination address.
     * @param data Optional data included in the transaction.
     */
    function transfer(
        address to,
        bytes calldata data
    ) external payable;

    /**
     * @dev Transfer tokens to a specified address.
     * @param token The token contract address.
     * @param to The destination address.
     * @param value The amount of tokens to be transferred.
     * @param data Optional data included in the transaction.
     */
    function transferToken(
        address token,
        address to,
        uint value,
        bytes calldata data
    ) external payable;
}