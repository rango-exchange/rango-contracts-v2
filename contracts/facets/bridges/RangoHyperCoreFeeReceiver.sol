// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IMessageTransmitterV2} from "../../interfaces/IMessageTransmitterV2.sol";
import {ICCTPTokenMinter} from "../../interfaces/ICCTPTokenMinter.sol";
import "../base/RangoBaseInterchainMiddlewareV2.sol";
import "../../utils/ReentrancyGuard.sol";

/// @title Receives HyperCore withdrawals and splits them between up to two referrers and the user
/// @author Sunny
/// @dev Deployed separately; not a facet. Ownership/pause/refund come from the base.
/// @dev Does no CALL and no swap — only mints the CCTP token and transfers it — so it never
///      whitelists anything. The whitelists-storage address is wired only for the base's shared
///      pause registry (onlyWhenNotPaused).
contract RangoHyperCoreFeeReceiver is ReentrancyGuard, RangoBaseInterchainMiddlewareV2 {
    bytes32 internal constant HYPERCORE_FEE_RECEIVER_NAMESPACE =
        keccak256("exchange.rango.middleware.hypercorefeereceiver");

    struct FeeReceiverStorage {
        address messageTransmitterV2;
        address tokenMinter;
    }

    /// @dev CCTP V2 message field offsets, sliced from calldata.
    ///      Header (148): version(4) sourceDomain(4) destinationDomain(4) nonce(32) sender(32)
    ///      recipient(32) destinationCaller(32) minFinalityThreshold(4) finalityThresholdExecuted(4)
    ///      Body (228): version(4) burnToken(32) mintRecipient(32) amount(32) messageSender(32)
    ///      maxFee(32) feeExecuted(32) expirationBlock(32)
    uint256 private constant OFFSET_SOURCE_DOMAIN = 4;
    uint256 private constant OFFSET_BURN_TOKEN = 152;
    uint256 private constant OFFSET_AMOUNT = 216;
    uint256 private constant OFFSET_FEE_EXECUTED = 312;
    uint256 private constant OFFSET_HOOK_DATA = 376;

    /// @dev Circle's CrossChainWithdrawalHookData envelope (abi.encodePacked):
    ///      magic(24) version(4) declaredLen(4)=28+payload from(20) coreNonce(8) payload(..)
    uint256 private constant ENVELOPE_LENGTH = 60;
    uint32 private constant ENVELOPE_VERSION = 0;

    /// @dev Packed payload, read positionally: a fixed 43-byte header then a variable array of up
    ///      to MAX_FEES referral entries (well within Circle's 1024-byte hook cap):
    ///      header:   version(1) requestId(20) recipient(20) dAppTag(2)
    ///      each fee: referrer(20) bps(2)
    ///      payload length = HEADER_LENGTH + FEE_ENTRY_LENGTH * feeCount; the fee count is derived
    ///      from the length, so there is no separate count field to disagree with it.
    uint256 private constant HEADER_LENGTH = 43;
    uint256 private constant FEE_ENTRY_LENGTH = 22;
    uint256 private constant MAX_FEES = 8;
    uint8 private constant PAYLOAD_VERSION = 2;

    uint256 private constant BPS_DENOMINATOR = 10_000;
    uint256 private constant MAX_TOTAL_FEE_BPS = 2_000; // 20% across all fees

    event CCTPConfigUpdated(address messageTransmitterV2, address tokenMinter);
    event RangoUserRefunded(address indexed recipient, address token, uint256 indexed amount);
    event HyperCoreWithdrawalReceived(address indexed coreSender, uint64 coreNonce);
    event ReferralFeePaid(address indexed referrer, address indexed token, uint256 amount, uint16 bps);
    event WithdrawalCompleted(
        address indexed requestId, address indexed token, address indexed recipient, uint256 amount, uint16 dAppTag
    );

    error ZeroAddress();
    error MessageTooShort(uint256 length);
    error InvalidEnvelope();
    error InvalidPayloadLength(uint256 length);
    error UnsupportedPayloadVersion(uint8 version);
    error InvalidRecipient();
    error InvalidReferrer();
    error TooManyFees(uint256 count);
    error FeeTooHigh(uint256 totalBps);
    error MessageTransmissionFailed();
    error ReceivedAmountMismatch(address token, uint256 expected, uint256 actual);

    /// @notice Sets owner + pause-registry wiring (base) and the CCTP config in one call.
    /// @dev onlyOwner; the base constructor already set owner to the deployer, so this can't be
    ///      front-run. `_whitelistsContract` backs the pause registry only.
    function initHyperCoreFeeReceiver(
        address _owner,
        address _messageTransmitterV2,
        address _tokenMinter,
        address _whitelistsContract
    ) external onlyOwner {
        if (_messageTransmitterV2 == address(0) || _tokenMinter == address(0)) revert ZeroAddress();
        initBaseMiddleware(_owner, _whitelistsContract);
        FeeReceiverStorage storage s = getFeeReceiverStorage();
        s.messageTransmitterV2 = _messageTransmitterV2;
        s.tokenMinter = _tokenMinter;
        emit CCTPConfigUpdated(_messageTransmitterV2, _tokenMinter);
    }

    function updateCCTPConfig(address _messageTransmitterV2, address _tokenMinter) external onlyOwner {
        if (_messageTransmitterV2 == address(0) || _tokenMinter == address(0)) revert ZeroAddress();
        FeeReceiverStorage storage s = getFeeReceiverStorage();
        s.messageTransmitterV2 = _messageTransmitterV2;
        s.tokenMinter = _tokenMinter;
        emit CCTPConfigUpdated(_messageTransmitterV2, _tokenMinter);
    }

    /// @notice Mints a message and sends the USDC straight to a recipient, ignoring the payload.
    /// @dev Recovery path for messages `callReceiveMessageFromHyperCore` cannot process — e.g. a
    ///      corrupt/unsupported payload whose funds are otherwise stuck burned at the CCTP layer.
    ///      onlyOwner: `_recipient`/`_amount` are owner-supplied precisely because the payload may
    ///      be the corrupt part and cannot be trusted.
    function processMessageAndTransferUSDC(
        bytes calldata message,
        bytes calldata signature,
        address _recipient,
        address _mintToken,
        uint256 _amount
    ) external nonReentrant onlyOwner {
        FeeReceiverStorage storage s = getFeeReceiverStorage();
        if (!IMessageTransmitterV2(s.messageTransmitterV2).receiveMessage(message, signature)) {
            revert MessageTransmissionFailed();
        }
        SafeERC20.safeTransfer(IERC20(_mintToken), _recipient, _amount);
        emit RangoUserRefunded(_recipient, _mintToken, _amount);
    }

    function getMessageTransmitterV2() external view returns (address) {
        return getFeeReceiverStorage().messageTransmitterV2;
    }

    function getTokenMinter() external view returns (address) {
        return getFeeReceiverStorage().tokenMinter;
    }

    /// @notice Mints the withdrawal's USDC and splits it between up to two referrers and the recipient.
    /// @dev Permissionless: CCTP sets destinationCaller to zero and the attested payload fixes the
    ///      payout, so anyone may relay. Fetch `message`/`signature` from the CCTP Iris API.
    function callReceiveMessageFromHyperCore(bytes calldata message, bytes calldata signature)
        external
        nonReentrant
        onlyWhenNotPaused
    {
        if (message.length < OFFSET_HOOK_DATA + ENVELOPE_LENGTH + HEADER_LENGTH) {
            revert MessageTooShort(message.length);
        }

        bytes calldata envelope = message[OFFSET_HOOK_DATA:];
        bytes calldata payload = envelope[ENVELOPE_LENGTH:];

        if (
            uint32(bytes4(envelope[24:28])) != ENVELOPE_VERSION
                || uint32(bytes4(envelope[28:32])) != payload.length + 28
        ) revert InvalidEnvelope();

        if (uint8(payload[0]) != PAYLOAD_VERSION) revert UnsupportedPayloadVersion(uint8(payload[0]));
        // fee entries must tile the payload exactly and stay within the cap
        uint256 feesBytes = payload.length - HEADER_LENGTH;
        if (feesBytes % FEE_ENTRY_LENGTH != 0) revert InvalidPayloadLength(payload.length);
        if (feesBytes / FEE_ENTRY_LENGTH > MAX_FEES) revert TooManyFees(feesBytes / FEE_ENTRY_LENGTH);

        FeeReceiverStorage storage s = getFeeReceiverStorage();

        address mintToken = ICCTPTokenMinter(s.tokenMinter).getLocalToken(
            uint32(bytes4(message[OFFSET_SOURCE_DOMAIN:OFFSET_SOURCE_DOMAIN + 4])),
            bytes32(message[OFFSET_BURN_TOKEN:OFFSET_BURN_TOKEN + 32])
        );

        // Circle deducts a variable feeExecuted from the burn before minting
        uint256 received = uint256(bytes32(message[OFFSET_AMOUNT:OFFSET_AMOUNT + 32]))
            - uint256(bytes32(message[OFFSET_FEE_EXECUTED:OFFSET_FEE_EXECUTED + 32]));

        uint256 balanceBefore = IERC20(mintToken).balanceOf(address(this));
        if (!IMessageTransmitterV2(s.messageTransmitterV2).receiveMessage(message, signature)) {
            revert MessageTransmissionFailed();
        }
        uint256 balanceAfter = IERC20(mintToken).balanceOf(address(this));
        if (balanceAfter < balanceBefore + received) {
            revert ReceivedAmountMismatch(mintToken, balanceBefore + received, balanceAfter);
        }

        emit HyperCoreWithdrawalReceived(address(bytes20(envelope[32:52])), uint64(bytes8(envelope[52:60])));
        _payout(mintToken, received, payload);
    }

    /// @dev Split factored out to keep stack depth manageable. Validates every fee entry before
    ///      paying any, so a bad entry reverts without partial payout.
    function _payout(address mintToken, uint256 received, bytes calldata payload) private {
        address recipient = address(bytes20(payload[21:41]));
        if (recipient == address(0)) revert InvalidRecipient();

        uint256 count = (payload.length - HEADER_LENGTH) / FEE_ENTRY_LENGTH;

        // pass 1: sum shares and validate referrers, enforce the combined cap
        uint256 totalBps;
        for (uint256 i = 0; i < count; ++i) {
            uint256 off = HEADER_LENGTH + i * FEE_ENTRY_LENGTH;
            uint16 bps = uint16(bytes2(payload[off + 20:off + 22]));
            if (bps == 0) continue;
            if (address(bytes20(payload[off:off + 20])) == address(0)) revert InvalidReferrer();
            totalBps += bps;
        }
        if (totalBps > MAX_TOTAL_FEE_BPS) revert FeeTooHigh(totalBps);

        // pass 2: pay each referrer; totalBps <= MAX_TOTAL_FEE_BPS < BPS_DENOMINATOR, so the
        // remainder to the recipient cannot underflow and rounding dust falls to the recipient
        uint256 totalFee;
        for (uint256 i = 0; i < count; ++i) {
            uint256 off = HEADER_LENGTH + i * FEE_ENTRY_LENGTH;
            uint16 bps = uint16(bytes2(payload[off + 20:off + 22]));
            if (bps == 0) continue;
            address referrer = address(bytes20(payload[off:off + 20]));
            uint256 fee = (received * bps) / BPS_DENOMINATOR;
            totalFee += fee;
            SafeERC20.safeTransfer(IERC20(mintToken), referrer, fee);
            emit ReferralFeePaid(referrer, mintToken, fee, bps);
        }

        uint256 net = received - totalFee;
        SafeERC20.safeTransfer(IERC20(mintToken), recipient, net);

        emit WithdrawalCompleted(
            address(bytes20(payload[1:21])), mintToken, recipient, net, uint16(bytes2(payload[41:43]))
        );
    }

    function getFeeReceiverStorage() private pure returns (FeeReceiverStorage storage s) {
        bytes32 namespace = HYPERCORE_FEE_RECEIVER_NAMESPACE;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            s.slot := namespace
        }
    }
}
