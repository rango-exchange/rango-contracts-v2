// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

interface ICCTPReciever {
    struct CCTPV2MessageBody {
        uint32 version;
        bytes32 burnToken;
        bytes32 recipient;
        uint256 amount;
        bytes32 messageSender;
        uint256 maxFee;
        uint256 feeExecuted;
        uint256 expirationBlock;
        bytes hookData;
    }

    struct CCTPV2Message {
        uint32 version;
        uint32 sourceDomain;
        uint32 destinationDomain;
        bytes32 nonce;
        bytes32 sender;
        bytes32 recipient;
        bytes32 destinationCaller;
        uint32 minFinalityThreshold;
        uint32 finalityThresholdExecuted;
        bytes messageBody;
    }

    function callRecieveMessage(bytes calldata message, bytes calldata signature) external;
    
    function processMessageAndTransferUSDC(
        bytes calldata message,
        bytes calldata signature,
        address _recipient,
        address _mintToken,
        uint256 _amount
    ) external;
}
