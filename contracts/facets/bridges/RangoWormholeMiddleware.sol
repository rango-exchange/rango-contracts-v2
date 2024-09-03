// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import "../../libraries/LibInterchain.sol";
import "../../utils/ReentrancyGuard.sol";
import "../base/RangoBaseInterchainMiddleware.sol";
import "../../interfaces/IWormholeRouter.sol";
import "../../interfaces/IWormhole.sol";
import "../../interfaces/IWormholeTokenBridge.sol";
import "../../interfaces/WormholeBridgeStructs.sol";

/// @title The middleware contract that handles Rango's receive messages from wormhole.
/// @author AMA
/// @dev Note that this is not a facet and should be deployed separately.
contract RangoWormholeMiddleware is ReentrancyGuard, IRango, RangoBaseInterchainMiddleware {
    /// Storage ///
    bytes32 internal constant WORMHOLE_MIDDLEWARE_NAMESPACE = keccak256("exchange.rango.middleware.wormhole");

    struct RangoWormholeMiddlewareStorage {
        address wormholeRouter;
        // @notice hashes of the transactions that should be refunded
        mapping(bytes32 => bool) refundHashes;
        // @notice for refunds where payload cannot be decoded to get recipient, therefore the receiver address is set manually
        mapping(bytes32 => address) refundHashAddresses;
    }

    function initWormholeMiddleware(
        address _owner,
        address _wormholeRouter,
        address whitelistsContract
    ) external onlyOwner {
        initBaseMiddleware(_owner, whitelistsContract);
        updateWormholeRouterAddressInternal(_wormholeRouter);
    }

    /// Events

    /// @notice Emits when the Wormhole address is updated
    /// @param oldAddress The previous address
    /// @param newAddress The new address
    event WormholeRouterAddressUpdated(address oldAddress, address newAddress);
    /// @notice Emitted when a refund state is updated
    /// @param refundHash The hash of data for which state is changed
    /// @param enabled The boolean signaling the state. true value means refund is enabled.
    /// @param refundAddress The address that should receive the refund.
    event RefundHashStateUpdated(bytes32 indexed refundHash, bool enabled, address refundAddress);
    /// @notice Emitted when a refund has been executed
    /// @param refundHash The hash of data for which state is changed
    /// @param refundAddress The address that should receive the refund.
    event PayloadHashRefunded(bytes32 indexed refundHash, address refundAddress);

    /// External Functions

    /// @notice Updates the address of wormholeRouter
    /// @param newAddress The new address of owner
    function updateWormholeRouter(address newAddress) external onlyOwner {
        updateWormholeRouterAddressInternal(newAddress);
    }

    /// @notice Add payload hashes to refund the user.
    /// @param hashes Array of payload hashes to be enabled or disabled for refund
    /// @param booleans Array of booleans corresponding to the hashes. true value means enable refund.
    /// @param addresses addresses that should receive the refund. Can be 0x0000 if the refund should be done based on interchain message
    function updateRefundHashes(
        bytes32[] calldata hashes,
        bool[] calldata booleans,
        address[] calldata addresses
    ) external onlyOwner {
        updateRefundHashesInternal(hashes, booleans, addresses);
    }

    /// @dev only callable by owner.
    function RefundWithPayloadAndSend(
        bytes calldata vaas,
        address expectedToken,
        address refundAddr,
        uint amount
    ) external nonReentrant onlyOwner {
        RangoWormholeMiddlewareStorage storage s = getRangoWormholeMiddlewareStorage();
        IWormholeTokenBridge whTokenBridge = IWormholeTokenBridge(s.wormholeRouter);
        whTokenBridge.completeTransferWithPayload(vaas);
        SafeERC20.safeTransfer(IERC20(expectedToken), refundAddr, amount);
        bytes32 refundHash = keccak256(vaas);
        emit PayloadHashRefunded(refundHash, refundAddr);
    }

    /// @param expectedToken the token that will be received from wormhole.
    /// @dev expected token be extracted from vaas but we pass it as argument to save gas. (see extractTokenAddressForVaas)
    function completeTransferWithPayload(
        address expectedToken,
        bytes memory vaas
    ) external nonReentrant onlyWhenNotPaused
    {
        RangoWormholeMiddlewareStorage storage s = getRangoWormholeMiddlewareStorage();
        IWormholeTokenBridge whTokenBridge = IWormholeTokenBridge(s.wormholeRouter);
        WormholeBridgeStructs.TransferWithPayload memory transfer;
        uint balanceBefore = IERC20(expectedToken).balanceOf(address(this));
        /// check for refund
        bytes32 refundHash = keccak256(vaas);
        if (s.refundHashes[refundHash] == true) {
            // transfer tokens to this contract
            transfer = whTokenBridge.parseTransferWithPayload(whTokenBridge.completeTransferWithPayload(vaas));
            require(expectedToken == extractTokenAddressFromTransferPayload(transfer));
            address refundAddr = s.refundHashAddresses[refundHash];
            address requestId = LibSwapper.ETH;
            address originalSender = LibSwapper.ETH;
            uint16 dAppTag;
            if (refundAddr == address(0)) {
                Interchain.RangoInterChainMessage memory im = abi.decode((transfer.payload), (Interchain.RangoInterChainMessage));
                refundAddr = im.recipient;
                requestId = im.requestId;
                originalSender = im.originalSender;
                dAppTag = im.dAppTag;
            }
            require(refundAddr != address(0), "Cannot refund to burn address");

            (,bytes memory queriedDecimalsRefund) = expectedToken.staticcall(abi.encodeWithSignature("decimals()"));
            uint256 exactAmountRefund = deNormalizeAmount(transfer.amount, abi.decode(queriedDecimalsRefund, (uint8)));
            require(IERC20(expectedToken).balanceOf(address(this)) - balanceBefore >= exactAmountRefund, "expected amount not transferred");
            SafeERC20.safeTransfer(IERC20(expectedToken), refundAddr, exactAmountRefund);
            s.refundHashes[refundHash] = false;
            s.refundHashAddresses[refundHash] = address(0);
            emit RefundHashStateUpdated(refundHash, false, refundAddr);
            emit PayloadHashRefunded(refundHash, refundAddr);
            emit RangoBridgeCompleted(
                requestId,
                expectedToken,
                originalSender,
                refundAddr,
                exactAmountRefund,
                CrossChainOperationStatus.RefundInDestination,
                dAppTag
            );

            return;
        }

        // wormhole sends token to our contract with this call
        transfer = whTokenBridge.parseTransferWithPayload(whTokenBridge.completeTransferWithPayload(vaas));
        require(expectedToken == extractTokenAddressFromTransferPayload(transfer));
        Interchain.RangoInterChainMessage memory m = abi.decode((transfer.payload), (Interchain.RangoInterChainMessage));

        (,bytes memory queriedDecimals) = expectedToken.staticcall(abi.encodeWithSignature("decimals()"));
        uint8 decimals = abi.decode(queriedDecimals, (uint8));

        // adjust decimals
        uint256 exactAmount = deNormalizeAmount(transfer.amount, decimals);
        require(IERC20(expectedToken).balanceOf(address(this)) - balanceBefore >= exactAmount, "expected amount not transferred");
        (address receivedToken, uint dstAmount, IRango.CrossChainOperationStatus status) = LibInterchain.handleDestinationMessage(
            expectedToken,
            exactAmount,
            m
        );
        emit RangoBridgeCompleted(
            m.requestId,
            receivedToken,
            m.originalSender,
            m.recipient,
            dstAmount,
            status,
            m.dAppTag
        );
    }

    function extractTokenAddressForVaas(bytes calldata vaas) public view returns (address){
        RangoWormholeMiddlewareStorage storage s = getRangoWormholeMiddlewareStorage();
        IWormholeTokenBridge whTokenBridge = IWormholeTokenBridge(s.wormholeRouter);
        IWormhole wh = IWormhole(whTokenBridge.wormhole());
        IWormhole.VM memory vm = wh.parseVM(vaas);
        WormholeBridgeStructs.TransferWithPayload memory transfer = whTokenBridge.parseTransferWithPayload(vm.payload);

        // extract token address
        if (transfer.tokenChain == whTokenBridge.chainId()) {
            return address(uint160(uint256(transfer.tokenAddress)));
        } else {
            address tmpWrappedAsset = whTokenBridge.wrappedAsset(transfer.tokenChain, transfer.tokenAddress);
            require(tmpWrappedAsset != LibSwapper.ETH, "Address is zero");
            return tmpWrappedAsset;
        }
    }

    function extractTokenAddressFromTransferPayload(WormholeBridgeStructs.TransferWithPayload memory transfer)
    internal view returns (address){
        RangoWormholeMiddlewareStorage storage s = getRangoWormholeMiddlewareStorage();
        IWormholeTokenBridge whTokenBridge = IWormholeTokenBridge(s.wormholeRouter);
        // extract token address
        if (transfer.tokenChain == whTokenBridge.chainId()) {
            return address(uint160(uint256(transfer.tokenAddress)));
        } else {
            address tmpWrappedAsset = whTokenBridge.wrappedAsset(transfer.tokenChain, transfer.tokenAddress);
            require(tmpWrappedAsset != LibSwapper.ETH, "Address is zero");
            return tmpWrappedAsset;
        }
    }

    function deNormalizeAmount(uint256 amount, uint8 decimals) internal pure returns (uint256){
        if (decimals > 8) {
            amount *= 10 ** (decimals - 8);
        }
        return amount;
    }

    function updateRefundHashesInternal(bytes32[] calldata hashes, bool[] calldata booleans, address[] calldata addresses) private {
        require(hashes.length == booleans.length && booleans.length == addresses.length);
        RangoWormholeMiddlewareStorage storage s = getRangoWormholeMiddlewareStorage();
        bytes32 hash;
        bool enabled;
        address refundAddr;
        for (uint256 i = 0; i < hashes.length; i++) {
            hash = hashes[i];
            enabled = booleans[i];
            s.refundHashes[hash] = enabled;
            refundAddr = addresses[i];
            if (refundAddr != address(0))
                s.refundHashAddresses[hash] = refundAddr;
            emit RefundHashStateUpdated(hash, enabled, refundAddr);
        }
    }

    /// Private and Internal
    function updateWormholeRouterAddressInternal(address newAddress) private {
        require(newAddress != LibSwapper.ETH, "Invalid Wormhole Address");
        RangoWormholeMiddlewareStorage storage s = getRangoWormholeMiddlewareStorage();
        address oldAddress = s.wormholeRouter;
        s.wormholeRouter = newAddress;
        emit WormholeRouterAddressUpdated(oldAddress, newAddress);
    }

    /// @dev fetch local storage
    function getRangoWormholeMiddlewareStorage() private pure returns (RangoWormholeMiddlewareStorage storage s) {
        bytes32 namespace = WORMHOLE_MIDDLEWARE_NAMESPACE;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            s.slot := namespace
        }
    }
}