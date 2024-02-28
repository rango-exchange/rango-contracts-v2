// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.16;

/// @title The root contract that handles Rango's interaction with Router Nitro Asset Forwarder
/// @author Shivam Agrawal
interface IRouterNitroAssetForwarder {
    struct DepositData {
        uint256 partnerId;
        uint256 amount;
        uint256 destAmount;
        address srcToken;
        address refundRecipient;
        bytes32 destChainIdBytes;
    }

    function iDeposit(
        DepositData memory depositData,
        bytes memory destToken,
        bytes memory recipient
    ) external payable;

    function iDepositMessage(
        DepositData memory depositData,
        bytes memory destToken,
        bytes memory recipient,
        bytes memory message
    ) external payable;
}
