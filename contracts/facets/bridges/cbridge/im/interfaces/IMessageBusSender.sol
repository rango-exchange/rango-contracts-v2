// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

interface IMessageBusSender {
    function calcFee(bytes calldata _message) external view returns (uint256);
}