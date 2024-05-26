// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25; 

import "../../libraries/LibInterchain.sol";
import "../../utils/ReentrancyGuard.sol";
import "../base/RangoBaseInterchainMiddleware.sol";
import "../../interfaces/INitroAssetForwarderMessageHandler.sol";

/// @title The middleware contract that handles Rango's receive messages from nitro asset forwarder.
/// @author George
/// @dev Note that this is not a facet and should be deployed separately.
contract RangoNitroAssetForwarderMiddleware is IRango, ReentrancyGuard, RangoBaseInterchainMiddleware, NitroAssetForwarderMessageHandler {
    /// @dev keccak256("exchange.rango.middleware.nitro_asset_forwarder")
    bytes32 internal constant NITRO_ASSET_FORWARDER_MIDDLEWARE_NAMESPACE = hex"c4c0b9311354e098fc4bf86672c92ca34c6037c8eef7a20b7b66bcce525505fc";

    address internal constant EEE_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    struct RangoNitroAssetForwarderMiddlewareStorage {
        /// @notice Address that can call handleMessage on this contract
        address nitroAssetForwarder;
    }

    function initNitroAssetForwarderMiddleware(
        address _owner,
        address _nitroAssetForwarder,
        address whitelistsContract
    ) external onlyOwner {
        initBaseMiddleware(_owner, whitelistsContract);
        updateNitroAssetForwarderAddressInternal(_nitroAssetForwarder);
    }

    /// Events
    /// @notice Emits when the Nitro asset forwarder address is updated
    /// @param _oldAddress The previous address
    /// @param _newAddress The new address
    event NitroAssetForwarderAddressUpdated(
        address _oldAddress,
        address _newAddress
    );

    /// External Functions
    /// @notice Adds a list of new addresses to the whitelisted across callers
    /// @param _nitroAssetForwarder The list of callers to be whitelisted
    function updateNitroAssetForwarder(address _nitroAssetForwarder) public onlyOwner {
        updateNitroAssetForwarderAddressInternal(_nitroAssetForwarder);
    }

    function handleMessage(
        address tokenSent,
        uint256 amount,
        bytes memory message
    ) external payable {
        require(msg.sender == getRangoNitroAssetForwarderMiddlewareStorage().nitroAssetForwarder, "unauthorized caller");
        // Note: When this function is called, the caller have already sent erc20 token or native token to this contract.
        //       When received token is native, the received token address ix 0xeeee...
        address inputToken = tokenSent == EEE_ADDRESS ? address(0) : tokenSent;

        Interchain.RangoInterChainMessage memory m = abi.decode((message), (Interchain.RangoInterChainMessage));
        (address receivedToken, uint dstAmount, IRango.CrossChainOperationStatus status) = LibInterchain.handleDestinationMessage(inputToken, amount, m);

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
    function updateNitroAssetForwarderAddressInternal(address _nitroAssetForwarder) private {
        require(_nitroAssetForwarder != address(0), "invalid address");
        RangoNitroAssetForwarderMiddlewareStorage storage s = getRangoNitroAssetForwarderMiddlewareStorage();

        address oldAddress = s.nitroAssetForwarder;
        s.nitroAssetForwarder = _nitroAssetForwarder;
        emit NitroAssetForwarderAddressUpdated(oldAddress, _nitroAssetForwarder);
    }

    /// @dev fetch local storage
    function getRangoNitroAssetForwarderMiddlewareStorage() private pure returns (RangoNitroAssetForwarderMiddlewareStorage storage s) {
        bytes32 namespace = NITRO_ASSET_FORWARDER_MIDDLEWARE_NAMESPACE;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            s.slot := namespace
        }
    }
}