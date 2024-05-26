// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

/// @title The root contract that handles Rango's interaction with Router bridge
/// @author Uchiha Sasuke
interface IVoyager {
    function depositETH(
        uint8 destinationChainID,
        bytes32 resourceID,
        bytes calldata data,
        uint256[] memory flags,
        address[] memory path,
        bytes[] calldata dataTx,
        address feeTokenAddress
    ) external payable;
}