// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import "../../libraries/LibInterchain.sol";
import "../../interfaces/IStargateReceiver.sol";
import "../../utils/ReentrancyGuard.sol";
import "../base/RangoBaseInterchainMiddleware.sol";

/// @title The middleware contract that handles Rango's receive messages from stargate.
/// @author George
/// @dev Note that this is not a facet and should be deployed separately.
contract RangoStargateMiddleware is ReentrancyGuard, IRango, IStargateReceiver, RangoBaseInterchainMiddleware {

    /// @dev keccak256("exchange.rango.middleware.stargate")
    bytes32 internal constant STARGATE_MIDDLEWARE_NAMESPACE = hex"8f95700cb6d0d3fbe23970b0fed4ae8d3a19af1ff9db49b72f280b34bdf7bad8";

    struct RangoStargateMiddlewareStorage {
        address stargateComposer;
        address sgeth;
    }

    function initStargateMiddleware(
        address _owner,
        address _stargateComposer,
        address _whitelistsContract,
        address _sgeth
    ) external onlyOwner {
        initBaseMiddleware(_owner, _whitelistsContract);
        updateStargateComposerAndSGETHAddressInternal(_stargateComposer, _sgeth);
    }

    /// Events

    /// @notice Emits when the Stargate address is updated
    /// @param oldAddress The previous address
    /// @param newAddress The new SGETH address
    event StargateComposerAddressUpdated(address oldAddress, address newAddress, address oldSgethAddress, address sgethAddress);

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

    /// @dev fetch local storage
    function getRangoStargateMiddlewareStorage() private pure returns (RangoStargateMiddlewareStorage storage s) {
        bytes32 namespace = STARGATE_MIDDLEWARE_NAMESPACE;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            s.slot := namespace
        }
    }
}