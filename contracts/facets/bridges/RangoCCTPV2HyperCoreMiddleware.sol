// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import "./RangoCCTPV2Middleware.sol";
import {ICCTPReceiver} from "../../interfaces/ICCTPReceiver.sol";
import {ICCTPTokenMinter} from "../../interfaces/ICCTPTokenMinter.sol";

/// @title Middleware that receives CCTP V2 messages originated from HyperCore withdrawals (Circle CoreDepositWallet)
/// @author Sunny
/// @dev This is not a facet, its deployed separately.
/// @dev Extends RangoCCTPV2Middleware without modifying it. HyperCore withdrawals initiated via
///      Circle's CoreDepositWallet.coreReceiveWithData wrap the user-provided hookData in a 60-byte
///      CrossChainWithdrawalHookData envelope before the CCTP burn. The inherited callReceiveMessage
///      expects a bare abi.encoded RangoInterChainMessage, so this contract adds
///      callReceiveMessageFromHyperCore which strips the envelope first, then follows the exact same flow.
contract RangoCCTPV2HyperCoreMiddleware is RangoCCTPV2Middleware {
    /// @dev CCTP V2 message header: version(4) + sourceDomain(4) + destinationDomain(4) + nonce(32)
    ///      + sender(32) + recipient(32) + destinationCaller(32) + minFinalityThreshold(4) + finalityThresholdExecuted(4)
    uint256 internal constant CCTP_MESSAGE_HEADER_LENGTH = 148;
    /// @dev CCTP V2 burn message body fixed part: version(4) + burnToken(32) + mintRecipient(32) + amount(32)
    ///      + messageSender(32) + maxFee(32) + feeExecuted(32) + expirationBlock(32)
    uint256 internal constant CCTP_MESSAGE_BODY_FIXED_LENGTH = 228;
    /// @dev Circle CrossChainWithdrawalHookData envelope (abi.encodePacked by CoreDepositWallet):
    ///      Bytes 0-23:  bytes24 magic bytes ("cctp-forward" if forwarding, 0 otherwise)
    ///      Bytes 24-27: uint32  envelope version (0)
    ///      Bytes 28-31: uint32  length of (from + coreNonce + user data) = 28 + inner length
    ///      Bytes 32-51: address from (the HyperCore sender)
    ///      Bytes 52-59: uint64  HyperCore nonce
    ///      Bytes 60+:   bytes   user provided hookData (abi.encoded RangoInterChainMessage)
    uint256 internal constant HYPERCORE_ENVELOPE_LENGTH = 60;
    uint32 internal constant HYPERCORE_ENVELOPE_VERSION = 0;

    /// Events ///

    /// @notice Emitted when a HyperCore withdrawal message is successfully processed
    /// @param coreSender The HyperCore account that initiated the withdrawal
    /// @param coreNonce The HyperCore transaction nonce
    event HyperCoreWithdrawalReceived(address indexed coreSender, uint64 coreNonce);

    /// Errors ///
    error RangoCCTPV2HyperCoreMiddleware__InvalidHyperCoreHookData();

    /// @notice Executes the CCTP destination call for a message whose hookData was wrapped by Circle's CoreDepositWallet.
    /// @dev Same flow as the inherited callReceiveMessage, except the 60-byte CrossChainWithdrawalHookData
    ///      envelope is stripped from the hookData before decoding the RangoInterChainMessage.
    /// @dev The caller must retrieve the `message` and `attestation` (signature) from the CCTP Iris API:
    ///      https://iris-api.circle.com/v2/messages/19/?transactionHash=inboundTxHash
    /// @param message The message payload to be sent.
    /// @param signature The attestation signature provided by the CCTP Iris API.
    function callReceiveMessageFromHyperCore(bytes calldata message, bytes calldata signature)
        external
        nonReentrant
        onlyWhenNotPaused
    {
        CCTPV2Storage storage s = getCCTPV2HyperCoreStorage();

        ICCTPReceiver.CCTPV2Message memory decodedMessage = decodeMessage(message);
        ICCTPReceiver.CCTPV2MessageBody memory decodedMessageBody =
            decodeMessageBody(message[CCTP_MESSAGE_HEADER_LENGTH:]);

        // Strip Circle's CrossChainWithdrawalHookData envelope from the hookData
        bytes calldata wrappedHookData = message[CCTP_MESSAGE_HEADER_LENGTH + CCTP_MESSAGE_BODY_FIXED_LENGTH:];
        if (wrappedHookData.length < HYPERCORE_ENVELOPE_LENGTH) {
            revert RangoCCTPV2HyperCoreMiddleware__InvalidHyperCoreHookData();
        }
        bytes calldata innerHookData = wrappedHookData[HYPERCORE_ENVELOPE_LENGTH:];
        // envelope sanity checks: version and declared payload length (20 bytes address + 8 bytes nonce + data)
        if (
            uint32(bytes4(wrappedHookData[24:28])) != HYPERCORE_ENVELOPE_VERSION
                || uint32(bytes4(wrappedHookData[28:32])) != innerHookData.length + 28
        ) {
            revert RangoCCTPV2HyperCoreMiddleware__InvalidHyperCoreHookData();
        }
        address coreSender = address(bytes20(wrappedHookData[32:52]));
        uint64 coreNonce = uint64(bytes8(wrappedHookData[52:60]));

        // Get the mint token address from the token minter
        address mintToken = ICCTPTokenMinter(s.tokenMinter).getLocalToken(
            decodedMessage.sourceDomain, decodedMessageBody.burnToken
        );

        uint256 balanceBefore = IERC20(mintToken).balanceOf(address(this));
        // Call the receiveMessage function of the message transmitter
        if (!IMessageTransmitterV2(s.messageTransmitterV2).receiveMessage(message, signature)) {
            revert RangoCCTPV2Middleware__MessageTransmissionFailed();
        }
        uint256 balanceAfter = IERC20(mintToken).balanceOf(address(this));

        if (balanceAfter < balanceBefore + decodedMessageBody.amount - decodedMessageBody.feeExecuted) {
            revert RangoCCTPV2Middleware__ReceivedAmountMismatch(
                mintToken, balanceBefore + decodedMessageBody.amount - decodedMessageBody.feeExecuted, balanceAfter
            );
        }

        Interchain.RangoInterChainMessage memory m =
            abi.decode(innerHookData, (Interchain.RangoInterChainMessage));
        (address receivedToken, uint256 dstAmount, IRango2.CrossChainOperationStatus status) = LibInterchainV2
            .handleDestinationMessage(
            mintToken,
            decodedMessageBody.amount - decodedMessageBody.feeExecuted,
            m
        );

        emit HyperCoreWithdrawalReceived(coreSender, coreNonce);
        emit RangoBridgeCompleted(
            m.requestId, receivedToken, m.originalSender, m.recipient, dstAmount, status, m.dAppTag
        );
    }

    /// @dev fetch local storage; same namespace as the parent so init/update functions apply here too
    function getCCTPV2HyperCoreStorage() private pure returns (CCTPV2Storage storage s) {
        bytes32 namespace = CCTPV2_MIDDLEWARE_NAMESPACE;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            s.slot := namespace
        }
    }
}
