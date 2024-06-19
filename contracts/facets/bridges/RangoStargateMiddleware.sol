// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import "../../libraries/LibInterchain.sol";
import "../../interfaces/IStargateReceiver.sol";
import "../../interfaces/IStargateV2.sol";
import "../../utils/ReentrancyGuard.sol";
import "../base/RangoBaseInterchainMiddleware.sol";

/// @title The middleware contract that handles Rango's receive messages from stargate.
/// @author George
/// @dev Note that this is not a facet and should be deployed separately.
contract RangoStargateMiddleware is ReentrancyGuard, IRango, IStargateReceiver, RangoBaseInterchainMiddleware {
    /// Storage ///
    bytes32 internal constant STARGATE_MIDDLEWARE_NAMESPACE = keccak256("exchange.rango.middleware.stargate");
    
    /// params for decoding stargateV2 messages
    uint8 private constant SRC_EID_OFFSET = 12;
    uint8 private constant AMOUNT_LD_OFFSET = 44;
    uint8 private constant COMPOSE_FROM_OFFSET = 76; // OFTComposeMsgCodec

    struct RangoStargateMiddlewareStorage {
        address stargateComposer;
        address sgeth;
        address stargateV2Treasurer; 
        address layerzeroEndpoint;
    }

    function initStargateMiddleware(
        address _owner,
        address _stargateComposer,
        address _whitelistsContract,
        address _sgeth,
        address _stargateV2Treasurer,
        address _stargateV2Endpoint
    ) external onlyOwner {
        initBaseMiddleware(_owner, _whitelistsContract);
        updateStargateComposerAndSGETHAddressInternal(_stargateComposer, _sgeth);
        updateStargateTreasurerAndEndpointInternal(_stargateV2Treasurer, _stargateV2Endpoint);
    }

    /// Events

    /// @notice Emits when the Stargate address is updated
    /// @param oldAddress The previous address
    /// @param newAddress The new SGETH address
    event StargateComposerAddressUpdated(address oldAddress, address newAddress, address oldSgethAddress, address sgethAddress);

    /// @notice Emits when the Stargate address is updated
    /// @param oldTreasurerAddress The previous Treasurer address
    /// @param newTreasurerAddress The new Treasurer address
    /// @param oldEndpointAddress The previous Endpoint address
    /// @param newEndpointAddress The new Endpoint address
    event StargateV2TreasurerAndEndpointAddressUpdated(address oldTreasurerAddress, address newTreasurerAddress, address oldEndpointAddress, address newEndpointAddress);

    /// External Functions

    /// @notice Updates the address of StargateComposer
    /// @param newComposerAddress The new address of composer
    function updateStargateComposer(address newComposerAddress) external onlyOwner {
        RangoStargateMiddlewareStorage storage s = getRangoStargateMiddlewareStorage();
        updateStargateComposerAndSGETHAddressInternal(newComposerAddress, s.sgeth);
    }

    /// @notice Updates the address of SGETH Address
    /// @param sgethAddress The new address of SGETH
    function updateStargetSGETH(address sgethAddress) external onlyOwner {
        RangoStargateMiddlewareStorage storage s = getRangoStargateMiddlewareStorage();
        updateStargateComposerAndSGETHAddressInternal(s.stargateComposer, sgethAddress);
    }

    /// @notice Updates the address of stargate v2 treasurer and endpoint
    /// @param newTreasurerAddress The new address of treasurer
    /// @param newEndpointAddress The new address of endpoint
    function updateStargateV2TreasurerAndEndpoint(address newTreasurerAddress, address newEndpointAddress) external onlyOwner {
        updateStargateTreasurerAndEndpointInternal(newTreasurerAddress, newEndpointAddress);
    }

    function lzCompose(
        address _from,
        bytes32,
        bytes calldata _message,
        address,
        bytes calldata
    ) external payable {
        RangoStargateMiddlewareStorage storage s = getRangoStargateMiddlewareStorage();
        require(msg.sender == s.layerzeroEndpoint, "invalid sender");
        require(IStargateV2Treasurer(s.stargateV2Treasurer).stargates(_from) == true, "invalid stargate");
        // get token address from the stargate pool
        address bridgeToken = IStargateV2Pool(_from).token();
        
        bytes calldata rangoMessageBytes = _message[COMPOSE_FROM_OFFSET:];
        Interchain.RangoInterChainMessage memory m = abi.decode((rangoMessageBytes), (Interchain.RangoInterChainMessage));
        uint256 amountLD = uint256(bytes32(_message[SRC_EID_OFFSET:AMOUNT_LD_OFFSET]));

        (address receivedToken, uint dstAmount, IRango.CrossChainOperationStatus status) = LibInterchain.handleDestinationMessage(bridgeToken, amountLD, m);

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

    // @param _chainId The remote chainId sending the tokens
    // @param _srcAddress The remote Bridge address
    // @param _nonce The message ordering nonce
    // @param _token The token contract on the local chain
    // @param amountLD The qty of local _token contract tokens
    // @param _payload The bytes containing the _tokenOut, _deadline, _amountOutMin, _toAddr
    function sgReceive(
        uint16,
        bytes memory,
        uint256,
        address _token,
        uint256 amountLD,
        bytes memory payload
    ) external payable override nonReentrant {
        require(msg.sender == getRangoStargateMiddlewareStorage().stargateComposer,
            "sgReceive function can only be called by Stargate Composer");
        Interchain.RangoInterChainMessage memory m = abi.decode((payload), (Interchain.RangoInterChainMessage));
        address bridgeToken = _token;
        if (_token == getRangoStargateMiddlewareStorage().sgeth) {
            bridgeToken = LibSwapper.ETH;
        }
        (address receivedToken, uint dstAmount, IRango.CrossChainOperationStatus status) = LibInterchain.handleDestinationMessage(bridgeToken, amountLD, m);

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
    function updateStargateComposerAndSGETHAddressInternal(address newComposerAddress, address sgethAddress) private {
        require(newComposerAddress != address(0), "Invalid StargateComposer");
        RangoStargateMiddlewareStorage storage s = getRangoStargateMiddlewareStorage();
        address oldComposerAddress = s.stargateComposer;
        s.stargateComposer = newComposerAddress;

        address oldSgethAddress = s.sgeth;
        s.sgeth = sgethAddress;
        emit StargateComposerAddressUpdated(oldComposerAddress, newComposerAddress, oldSgethAddress, sgethAddress);
    }

    function updateStargateTreasurerAndEndpointInternal(address newTreasurerAddress, address newEndpointAddress) private {
        RangoStargateMiddlewareStorage storage s = getRangoStargateMiddlewareStorage();
        address oldTreasurer = s.stargateV2Treasurer;
        s.stargateV2Treasurer = newTreasurerAddress;

        address oldEndpointAddress = s.layerzeroEndpoint;
        s.layerzeroEndpoint = newEndpointAddress;
        emit StargateV2TreasurerAndEndpointAddressUpdated(oldTreasurer, newTreasurerAddress, oldEndpointAddress, newEndpointAddress);
    }

    /// @dev fetch local storage
    function getRangoStargateMiddlewareStorage() private pure returns (RangoStargateMiddlewareStorage storage s) {
        bytes32 namespace = STARGATE_MIDDLEWARE_NAMESPACE;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            s.slot := namespace
        }
    }
}