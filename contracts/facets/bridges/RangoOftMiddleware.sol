// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import "../../interfaces/IOAppComposer.sol";
import "../../libraries/LibInterchainV2.sol";
import "../../utils/ReentrancyGuard.sol";
import "../base/RangoBaseInterchainMiddlewareV2.sol";

/// @title The middleware contract that handles Rango's receive messages from LayerZero.
/// @author 0x4rde
/// @dev Note that this is not a facet and should be deployed separately.
contract RangoOftMiddleware is ReentrancyGuard, IRango2, IOAppComposer, RangoBaseInterchainMiddlewareV2 {
    /// Storage ///
    bytes32 internal constant OFT_MIDDLEWARE_NAMESPACE = keccak256("exchange.rango.middleware.oft");
    /// params for decoding LayerZero compose messages (OFT format)
    uint8 private constant SRC_EID_OFFSET = 12;
    uint8 private constant AMOUNT_LD_OFFSET = 44;
    uint8 private constant COMPOSE_FROM_OFFSET = 76; // OFTComposeMsgCodec

    /// @notice An OApp (OFT contract) paired with the ERC20 it is authorized to deliver on this chain.
    /// @dev For a native OFT, `token` equals the OApp itself; for an OFT adapter, `token` is the
    ///      wrapped ERC20. This binding is what prevents a whitelisted low-value OApp from being
    ///      used to operate on an arbitrary (high-value) token the contract may hold.
    struct OappTokenPair {
        address oApp;
        address token;
    }

    struct RangoOftMiddlewareStorage {
        address oftEndpoint;
        // whitelisted OApps mapped to the single ERC20 each one is allowed to deliver.
        // address(0) => the OApp is not whitelisted.
        mapping(address => address) whitelistedOapps;
    }

    /// Events
    /// @notice Emits when the OFT endpoint address is updated
    /// @param oldAddress The previous endpoint address
    /// @param newAddress The new endpoint address
    event OftEndpointAddressUpdated(address oldAddress, address newAddress);
    /// @notice Emits when OApps are whitelisted
    /// @param oapps The list of OApp/token pairs that were whitelisted
    event OappsWhitelisted(OappTokenPair[] oapps);
    /// @notice Emits when OApps are removed from whitelist
    /// @param oapps The list of OApp addresses that were removed
    event OappsRemoved(address[] oapps);

    function initOftMiddleware(
        address _owner,
        address _oftEndpoint,
        OappTokenPair[] memory _whitelistedOapps,
        address _whitelistsContract
    ) external onlyOwner {
        initBaseMiddleware(_owner, _whitelistsContract);
        updateOftEndpointInternal(_oftEndpoint);
        addWhitelistedOappsInternal(_whitelistedOapps);
    }

    function updateOftEndpoint(address newEndpoint) external onlyOwner {
        updateOftEndpointInternal(newEndpoint);
    }

    function addWhitelistedOapps(OappTokenPair[] memory newWhitelistedOapps) external onlyOwner {
        addWhitelistedOappsInternal(newWhitelistedOapps);
    }

    function removeWhitelistedOapps(address[] memory oappsToRemove) external onlyOwner {
        if (oappsToRemove.length == 0) return;
        RangoOftMiddlewareStorage storage s = getRangoOftMiddlewareStorage();
        for (uint i = 0; i < oappsToRemove.length; i++) {
            delete s.whitelistedOapps[oappsToRemove[i]];
        }
        emit OappsRemoved(oappsToRemove);
    }

    function lzCompose(
        address _oApp,
        bytes32 /* _guid */,
        bytes calldata _message,
        address /* _executor */,
        bytes calldata /* _extraData */
    ) external payable override onlyWhenNotPaused nonReentrant {
        RangoOftMiddlewareStorage storage s = getRangoOftMiddlewareStorage();
        
        address bridgeToken = s.whitelistedOapps[_oApp];
        require(bridgeToken != address(0), "ComposedReceiver: Invalid OApp");
        require(msg.sender == s.oftEndpoint, "ComposedReceiver: Unauthorized sender");
        // Validate message length before slicing
        require(_message.length >= COMPOSE_FROM_OFFSET, "Message too short");

        bytes calldata rangoMessageBytes = _message[COMPOSE_FROM_OFFSET:];
        Interchain.RangoInterChainMessage memory m = abi.decode((rangoMessageBytes), (Interchain.RangoInterChainMessage));
        uint256 amountLD = uint256(bytes32(_message[SRC_EID_OFFSET:AMOUNT_LD_OFFSET]));

        (address receivedToken, uint dstAmount, IRango2.CrossChainOperationStatus status) = LibInterchainV2.handleDestinationMessage(bridgeToken, amountLD, m);

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

    /// @notice Returns the ERC20 a given OApp is whitelisted to deliver, or address(0) if not whitelisted.
    /// @param oApp The OApp (OFT contract) address
    /// @return the ERC20 token bound to the OApp
    function getWhitelistedOappToken(address oApp) external view returns (address) {
        return getRangoOftMiddlewareStorage().whitelistedOapps[oApp];
    }

    /// Private and Internal
    function updateOftEndpointInternal(address newEndpoint) private {
        require(newEndpoint != address(0), "Invalid OFT Endpoint");
        RangoOftMiddlewareStorage storage s = getRangoOftMiddlewareStorage();
        address oldEndpoint = s.oftEndpoint;
        s.oftEndpoint = newEndpoint;
        emit OftEndpointAddressUpdated(oldEndpoint, newEndpoint);
    }

    function addWhitelistedOappsInternal(OappTokenPair[] memory newWhitelistedOapps) private {
        if (newWhitelistedOapps.length == 0) return;
        RangoOftMiddlewareStorage storage s = getRangoOftMiddlewareStorage();
        for (uint i = 0; i < newWhitelistedOapps.length; i++) {
            require(newWhitelistedOapps[i].oApp != address(0), "Invalid OApp Address");
            require(newWhitelistedOapps[i].token != address(0), "Invalid OApp Token");
            s.whitelistedOapps[newWhitelistedOapps[i].oApp] = newWhitelistedOapps[i].token;
        }
        emit OappsWhitelisted(newWhitelistedOapps);
    }

    /// @dev fetch local storage
    function getRangoOftMiddlewareStorage() private pure returns (RangoOftMiddlewareStorage storage s) {
        bytes32 namespace = OFT_MIDDLEWARE_NAMESPACE;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            s.slot := namespace
        }
    }
}
