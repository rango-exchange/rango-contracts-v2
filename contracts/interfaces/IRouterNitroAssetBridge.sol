// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.16;

/// @title The root contract that handles Rango's interaction with Router Nitro Asset Bridge
/// @author Shivam Agrawal
interface IRouterNitroAssetBridge {
    struct TransferPayload {
        bytes32 destChainIdBytes;
        address srcTokenAddress;
        uint256 srcTokenAmount;
        bytes recipient;
        uint256 partnerId;
    }

    function transferToken(
        TransferPayload memory transferPayload
    ) external payable;

    function transferTokenWithInstruction(
        TransferPayload memory transferPayload,
        uint64 destGasLimit,
        bytes calldata instruction
    ) external payable;
}
