// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import "../../libraries/LibInterchain.sol";
import "../../utils/ReentrancyGuard.sol";
import "../base/RangoBaseInterchainMiddleware.sol";
import "../../interfaces/IConnextReceiver.sol";

/// @title The middleware contract that handles Rango's receive messages from Connext.
/// @author jeoffery
/// @dev Note that this is not a facet and should be deployed separately.
contract RangoConnextMiddleware is ReentrancyGuard, IRango, IConnextReceiver, RangoBaseInterchainMiddleware {

    /// @dev keccak256("exchange.rango.middleware.connext")
    bytes32 internal constant CONNEXT_MIDDLEWARE_NAMESPACE = hex"3b1e41b9e4a4adee2522104effda39f596c3c369174ba07a243347cbec17c71f";

    struct RangoConnextMiddlewareStorage {
        address connextBridge;
    }

    function initConnextMiddleware(
        address _owner,
        address _connextBridge,
        address _whitelistsContract
    ) external onlyOwner {
        initBaseMiddleware(_owner, _whitelistsContract);
        updateConnextBridgeAddressInternal(_connextBridge);
    }

    /// Events

    /// @notice Emits when the Connext bridge address is updated
    /// @param oldAddress The previous address
    /// @param newAddress The new address
    event ConnextBridgeAddressUpdated(address oldAddress, address newAddress);

    /// External Functions

    /// @notice Updates the address of connextBridge
    /// @param newAddress The new address of owner
    function updateConnextBridgeAddress(address newAddress) external onlyOwner {
        updateConnextBridgeAddressInternal(newAddress);
    }

    function xReceive(
        bytes32 _transferId,
        uint256 _amount,
        address _asset,
        address _originSender,
        uint32 _origin,
        bytes memory _callData
    ) external payable nonReentrant returns (bytes memory) {
        require(msg.sender == getRangoConnextMiddlewareStorage().connextBridge,
            "xReceive can only be called by Connext bridge");
        Interchain.RangoInterChainMessage memory m = abi.decode((_callData), (Interchain.RangoInterChainMessage));
        (address receivedToken, uint dstAmount, IRango.CrossChainOperationStatus status) = LibInterchain.handleDestinationMessage(_asset, _amount, m);

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
    function updateConnextBridgeAddressInternal(address newAddress) private {
        require(newAddress != address(0), "Invalid ConnextBridge");
        RangoConnextMiddlewareStorage storage s = getRangoConnextMiddlewareStorage();
        address oldAddress = s.connextBridge;
        s.connextBridge = newAddress;
        emit ConnextBridgeAddressUpdated(oldAddress, newAddress);
    }

    /// @dev fetch local storage
    function getRangoConnextMiddlewareStorage() private pure returns (RangoConnextMiddlewareStorage storage s) {
        bytes32 namespace = CONNEXT_MIDDLEWARE_NAMESPACE;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            s.slot := namespace
        }
    }
}