// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import "../../interfaces/IRango.sol";
import "../../interfaces/IDlnExternalCallExecutor.sol";
import "../../interfaces/IUniswapV2.sol";
import "../../interfaces/Interchain.sol";
import "../../libraries/LibInterchain.sol";
import "../base/RangoBaseInterchainMiddleware.sol";
import "../../utils/ReentrancyGuard.sol";

/// @title The contract that receives interchain messages. underlying dex is DLN that itself is based on deBridge
/// @author Jeoffery
/// @dev This is not a facet, its deployed separately.
contract RangoDeBridgeMiddleware is IRango, ReentrancyGuard, IExternalCallExecutor, RangoBaseInterchainMiddleware {
    /// Storage ///
    bytes32 internal constant DEBRIDGE_NAMESPACE = keccak256("exchange.rango.middleware.deBridge");

    struct DeBridgeStorage {
        /// @notice The address of dln external call adapter contract
        address dlnExtCallAdapterAddress;
    }

    /// @notice Emitted when the dln externalCallAdapter address is updated
    /// @param _oldAddress The previous address
    /// @param _newAddress The new address
    event DlnExtCallAdapterAddressUpdated(address _oldAddress, address _newAddress);

    function initDeBridgeMiddleware(
        address _owner,
        address _whitelistsContract,
        address _dlnExtCallAdapterAddress
    ) external onlyOwner {
        initBaseMiddleware(_owner, _whitelistsContract);
        updateDlnExtCallAdapterInternal(_dlnExtCallAdapterAddress);
    }

    /// @notice Updates the address of dln external call adapter contract
    /// @param _address The new address of dln external call adapter contract
    function updateDlnExtCallAdapterAddress(address _address) public onlyOwner {
        updateDlnExtCallAdapterInternal(_address);
    }

    function onEtherReceived(
        bytes32 _orderId,
        address _fallbackAddress,
        bytes memory _payload
    ) external payable returns (bool callSucceeded, bytes memory callResult) {
        require(msg.sender == getDeBridgeStorage().dlnExtCallAdapterAddress,
            "onEtherReceived function can only be called by dln ext call adapter");

        _onReceived(LibSwapper.ETH, msg.value, _payload);
        return (true, "0x");
    }

    function onERC20Received(
        bytes32 _orderId,
        address _token,
        uint256 _transferredAmount,
        address _fallbackAddress,
        bytes memory _payload
    ) external returns (bool callSucceeded, bytes memory callResult) {
        require(msg.sender == getDeBridgeStorage().dlnExtCallAdapterAddress,
            "onERC20Received function can only be called by dln ext call adapter");
        _onReceived(_token, _transferredAmount, _payload);
        return (true, "0x");
    }

    function _onReceived(
        address _token,
        uint256 _amount,
        bytes memory _payload
    ) internal {
        Interchain.RangoInterChainMessage memory m = abi.decode((_payload), (Interchain.RangoInterChainMessage));
        (address receivedToken, uint dstAmount, IRango.CrossChainOperationStatus status) = LibInterchain.handleDestinationMessage(_token, _amount, m);

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

    function updateDlnExtCallAdapterInternal(address _address) private {
        require(_address != address(0), "Invalid Adapter Address");
        DeBridgeStorage storage s = getDeBridgeStorage();
        address oldAddress = s.dlnExtCallAdapterAddress;
        s.dlnExtCallAdapterAddress = _address;
        emit DlnExtCallAdapterAddressUpdated(oldAddress, _address);
    }

    /// @dev fetch local storage
    function getDeBridgeStorage() private pure returns (DeBridgeStorage storage s) {
        bytes32 namespace = DEBRIDGE_NAMESPACE;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            s.slot := namespace
        }
    }
}
