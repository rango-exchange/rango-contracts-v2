// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import "../../interfaces/IUniswapV2.sol";
import "../../interfaces/IRangoMessageReceiver.sol";
import "../../interfaces/Interchain.sol";
import "../base/RangoBaseInterchainMiddlewareV2.sol";
import "../../utils/ReentrancyGuard.sol";
import "../../interfaces/IMessageTransmitterV2.sol";
import "../../utils/LibTransform.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ICCTPReceiver} from "../../interfaces/ICCTPReceiver.sol";
import {ICCTPTokenMinter} from "../../interfaces/ICCTPTokenMinter.sol";

/// @title The contract that receives interchain messages
/// @author Sunny
/// @dev This is not a facet, its deployed separately.
contract RangoCCTPV2Middleware is IRango2, ReentrancyGuard, ICCTPReceiver, RangoBaseInterchainMiddlewareV2 {
    using LibTransform for bytes32;

    /// Storage ///
    bytes32 internal constant CCTPV2_MIDDLEWARE_NAMESPACE = keccak256("exchange.rango.middleware.cctpv2");

    struct CCTPV2Storage {
        /// @notice The address of CCTP Transmitter contract
        address messageTransmitterV2;
        address tokenMinter;
    }

    /// Events ///
    event MessageTransmitterV2AddressUpdated(address _oldAddress, address _newAddress);
    event RangoUserRefunded(address indexed user, address token, uint256 indexed amount);

    /// Errors ///
    error RangoCCTPV2Middleware__InvalidMessageTransmitterV2Address();
    error RangoCCTPV2Middleware__MessageTransmissionFailed();
    error RangoCCTPV2Middleware__ReceivedAmountMismatch(
        address mintToken, uint256 expectedAmount, uint256 actualAmount
    );

    function initCCTPV2Middleware(address _owner, address _messageTransmitterV2, address _tokenMinterV2, address whitelistsContract)
        external
        onlyOwner
    {
        initBaseMiddleware(_owner, whitelistsContract);
        updateMessageTransmitterV2Internal(_messageTransmitterV2);
        updateTokenMinterV2Internal(_tokenMinterV2);
    }

    function updateMessageTransmitterV2(address _address) public onlyOwner {
        updateMessageTransmitterV2Internal(_address);
    }

    function updateTokenMinterV2(address _address) external onlyOwner {
        updateTokenMinterV2Internal(_address);
    }

    /// @notice Executes the CCTP destination call.
    /// @dev The caller must retrieve the `message` and `attestation` (signature) from the CCTP Iris API:
    ///      https://iris-api.circle.com/v2/messages/1/?transactionHash=inboundTxHash
    /// @param message The message payload to be sent.
    /// @param signature The attestation signature provided by the CCTP Iris API.
    function callReceiveMessage(bytes calldata message, bytes calldata signature)
        external
        nonReentrant
        onlyWhenNotPaused
    {
        CCTPV2Storage storage s = getCCTPV2Storage();
        
        CCTPV2Message memory decodedMessage = decodeMessage(message);
        CCTPV2MessageBody memory decodedMessageBody = this.decodeMessageBody(decodedMessage.messageBody);

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
            abi.decode((decodedMessageBody.hookData), (Interchain.RangoInterChainMessage));
        (address receivedToken, uint256 dstAmount, IRango2.CrossChainOperationStatus status) = LibInterchainV2
            .handleDestinationMessage(
            mintToken,
            decodedMessageBody.amount - decodedMessageBody.feeExecuted,
            m
        );

        emit RangoBridgeCompleted(
            m.requestId, receivedToken, m.originalSender, m.recipient, dstAmount, status, m.dAppTag
        );
    }

    /// @notice Processes the received message and transfers USDC to the user, ignoring hookData.
    /// @dev This function validates the message and signature by calling the MeassageTransmitter 
    /// then directly transfers the USDC to the recipient. meant to be used for refunding users in case of corrupted messages.
    /// @param message The message to be processed
    /// @param signature The attestation signature provided by the CCTP Iris API
    /// @param _recipient The address to which the USDC will be transferred
    /// @param _mintToken The token to be minted (USDC in most cases)
    function processMessageAndTransferUSDC(bytes calldata message, bytes calldata signature, address _recipient, address _mintToken, uint256 _amount)
        external
        nonReentrant
        onlyOwner
    {
        CCTPV2Storage storage s = getCCTPV2Storage();

        // Call the receiveMessage function of the message transmitter
        if (!IMessageTransmitterV2(s.messageTransmitterV2).receiveMessage(message, signature)) {
            revert RangoCCTPV2Middleware__MessageTransmissionFailed();
        }

        // Transfer USDC to the recipient
        SafeERC20.safeTransfer(IERC20(_mintToken), _recipient, _amount);
        emit RangoUserRefunded(_recipient, _mintToken, _amount);
    }

    function decodeMessageBody(bytes calldata messageBody)
        public
        pure
        returns (ICCTPReceiver.CCTPV2MessageBody memory decodedMessageBody)
    {
        assembly {
            // Allocate memory for the struct (8 fixed fields = 8 * 32 = 256 bytes) + 1 for dynamic
            decodedMessageBody := mload(0x40) // start of free memory
            let structOffset := decodedMessageBody
            mstore(0x40, add(structOffset, 0x120)) // reserve 288 bytes for struct

            // Set initial calldata offset
            let offset := messageBody.offset

            // version (uint32 in first 4 bytes)
            mstore(structOffset, shr(224, calldataload(offset))) // shift right by 224 bits (32-4 bytes)
            offset := add(offset, 0x04)

            // burnToken (bytes32)
            mstore(add(structOffset, 0x20), calldataload(offset))
            offset := add(offset, 0x20)

            // mintRecipient (bytes32)
            mstore(add(structOffset, 0x40), calldataload(offset))
            offset := add(offset, 0x20)

            // amount (uint256)
            mstore(add(structOffset, 0x60), calldataload(offset))
            offset := add(offset, 0x20)

            // messageSender (bytes32)
            mstore(add(structOffset, 0x80), calldataload(offset))
            offset := add(offset, 0x20)

            // maxFee (uint256)
            mstore(add(structOffset, 0xA0), calldataload(offset))
            offset := add(offset, 0x20)

            // feeExecuted (uint256)
            mstore(add(structOffset, 0xC0), calldataload(offset))
            offset := add(offset, 0x20)

            // expirationBlock (uint256)
            mstore(add(structOffset, 0xE0), calldataload(offset))
            offset := add(offset, 0x20)

            // hookData (bytes dynamic array)
            let hookDataLength := sub(messageBody.length, sub(offset, messageBody.offset))

            // Allocate memory for hookData
            let hookData := mload(0x40)
            mstore(hookData, hookDataLength) // length
            calldatacopy(add(hookData, 0x20), offset, hookDataLength)
            mstore(0x40, add(add(hookData, 0x20), hookDataLength)) // update free memory pointer

            // Store hookData pointer in struct
            mstore(add(structOffset, 0x100), hookData)
        }
    }

    function decodeMessage(bytes calldata message)
        public
        pure
        returns (ICCTPReceiver.CCTPV2Message memory decodedMessage)
    {
        assembly {
            // Allocate memory for struct (9 fixed fields + 1 dynamic = 320 bytes = 0x140)
            decodedMessage := mload(0x40)
            let structOffset := decodedMessage
            mstore(0x40, add(structOffset, 0x140)) // advance free memory pointer

            let offset := message.offset

            // version (uint32)
            mstore(structOffset, shr(224, calldataload(offset)))
            offset := add(offset, 0x04)

            // sourceDomain (uint32)
            mstore(add(structOffset, 0x20), shr(224, calldataload(offset)))
            offset := add(offset, 0x04)

            // destinationDomain (uint32)
            mstore(add(structOffset, 0x40), shr(224, calldataload(offset)))
            offset := add(offset, 0x04)

            // nonce (bytes32)
            mstore(add(structOffset, 0x60), calldataload(offset))
            offset := add(offset, 0x20)

            // sender (bytes32)
            mstore(add(structOffset, 0x80), calldataload(offset))
            offset := add(offset, 0x20)

            // recipient (bytes32)
            mstore(add(structOffset, 0xA0), calldataload(offset))
            offset := add(offset, 0x20)

            // destinationCaller (bytes32)
            mstore(add(structOffset, 0xC0), calldataload(offset))
            offset := add(offset, 0x20)

            // minFinalityThreshold (uint32)
            mstore(add(structOffset, 0xE0), shr(224, calldataload(offset)))
            offset := add(offset, 0x04)

            // finalityThresholdExecuted (uint32)
            mstore(add(structOffset, 0x100), shr(224, calldataload(offset)))
            offset := add(offset, 0x04)

            // messageBody (bytes)
            let messageBodyLength := sub(message.length, sub(offset, message.offset))

            let messageBody := mload(0x40)
            mstore(messageBody, messageBodyLength)
            calldatacopy(add(messageBody, 0x20), offset, messageBodyLength)
            mstore(0x40, add(add(messageBody, 0x20), messageBodyLength))

            mstore(add(structOffset, 0x120), messageBody)
        }
    }

    function updateMessageTransmitterV2Internal(address _address) private {
        if (_address == address(0)) {
            revert RangoCCTPV2Middleware__InvalidMessageTransmitterV2Address();
        }

        CCTPV2Storage storage s = getCCTPV2Storage();
        address oldAddress = s.messageTransmitterV2;
        s.messageTransmitterV2 = _address;
        emit MessageTransmitterV2AddressUpdated(oldAddress, _address);
    }

    function updateTokenMinterV2Internal(address _address) private {
        if (_address == address(0)) {
            revert RangoCCTPV2Middleware__InvalidMessageTransmitterV2Address();
        }

        CCTPV2Storage storage s = getCCTPV2Storage();
        address oldAddress = s.tokenMinter;
        s.tokenMinter = _address;
        emit MessageTransmitterV2AddressUpdated(oldAddress, _address);
    }

    function getCCTPV2Storage() private pure returns (CCTPV2Storage storage s) {
        bytes32 namespace = CCTPV2_MIDDLEWARE_NAMESPACE;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            s.slot := namespace
        }
    }
}
