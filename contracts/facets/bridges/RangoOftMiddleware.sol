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

    struct RangoOftMiddlewareStorage {
        address oftEndpoint;
        // oft tokens that are whitelisted to be used with this middleware
        //q? do we need to whitelist tokens? or can we receive message from any oapp? 
        mapping(address => bool) whitelistedOapps; 
    }

    /// Events
    /// @notice Emits when the OFT endpoint address is updated
    /// @param oldAddress The previous endpoint address
    /// @param newAddress The new endpoint address
    event OftEndpointAddressUpdated(address oldAddress, address newAddress);
    /// @notice Emits when OApps are whitelisted
    /// @param oapps The list of OApp addresses that were whitelisted
    event OappsWhitelisted(address[] oapps);
    /// @notice Emits when OApps are removed from whitelist
    /// @param oapps The list of OApp addresses that were removed
    event OappsRemoved(address[] oapps);

    function initOftMiddleware(
        address _owner,
        address _oftEndpoint,
        address[] memory _whitelistedOapps,
        address _whitelistsContract
    ) external onlyOwner {
        initBaseMiddleware(_owner, _whitelistsContract);
        updateOftEndpointInternal(_oftEndpoint);
        addWhitelistedOappsInternal(_whitelistedOapps);
    }

    function updateOftEndpoint(address newEndpoint) external onlyOwner {
        updateOftEndpointInternal(newEndpoint);
    }

    function addWhitelistedOapps(address[] memory newWhitelistedOapps) external onlyOwner {
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
        // Ensure the composed message comes from the correct OApp.
        require(s.whitelistedOapps[_oApp], "ComposedReceiver: Invalid OApp");
        require(msg.sender == s.oftEndpoint, "ComposedReceiver: Unauthorized sender");
        require(s.oftEndpoint != address(0), "OFT endpoint not initialized");
        // Validate message length before slicing
        require(_message.length >= COMPOSE_FROM_OFFSET, "Message too short");
        
        bytes calldata rangoMessageBytes = _message[COMPOSE_FROM_OFFSET:];
        Interchain.RangoInterChainMessage memory m = abi.decode((rangoMessageBytes), (Interchain.RangoInterChainMessage));
        
        //@dev using bridgeRealOutput to get the received token address is safe, because ETH (native) or WETH(weth) are not OFTs in any network.
        address bridgeToken = m.bridgeRealOutput;
        require(bridgeToken != address(0), "Invalid bridge token address");
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

    /// Private and Internal
    function updateOftEndpointInternal(address newEndpoint) private {
        require(newEndpoint != address(0), "Invalid OFT Endpoint");
        RangoOftMiddlewareStorage storage s = getRangoOftMiddlewareStorage();
        address oldEndpoint = s.oftEndpoint;
        s.oftEndpoint = newEndpoint;
        emit OftEndpointAddressUpdated(oldEndpoint, newEndpoint);
    }

    function addWhitelistedOappsInternal(address[] memory newWhitelistedOapps) private {
        if (newWhitelistedOapps.length == 0) return;
        RangoOftMiddlewareStorage storage s = getRangoOftMiddlewareStorage();
        for (uint i = 0; i < newWhitelistedOapps.length; i++) {
            require(newWhitelistedOapps[i] != address(0), "Invalid OApp Address");
            s.whitelistedOapps[newWhitelistedOapps[i]] = true;
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
