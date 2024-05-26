// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "../utils/DlnOrderData.sol";

// by using DLN (DeSwap Liqudidity Network), one can indirectly use DeBridge and get native and actual erc20 tokens in dst instead of De[Asset]

interface IDlnSource {
    function createSaltedOrder(
        OrderCreation calldata _orderCreation,
        uint64 _salt,
        bytes calldata _affiliateFee,
        uint32 _referralCode,
        bytes calldata _permitEnvelope,
        bytes memory _metadata
    ) external payable returns (bytes32 orderId);
}
