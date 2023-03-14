// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

/// @title The root contract that handles Rango's interaction with Hop bridge
/// @author Uchiha Sasuke
interface IHop {
    function swapAndSend(
        uint256 chainId,
        address recipient,
        uint256 amount,
        uint256 bonderFee,
        uint256 amountOutMin,
        uint256 deadline,
        uint256 destinationAmountOutMin,
        uint256 destinationDeadline
    ) external payable;

    function sendToL2(
        uint256 chainId,
        address recipient,
        uint256 amount,
        uint256 amountOutMin,
        uint256 deadline,
        address relayer,
        uint256 relayerFee
    ) external payable;
}