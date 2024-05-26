// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import "../../libraries/LibInterchain.sol";
import "../../utils/ReentrancyGuard.sol";
import "../base/RangoBaseInterchainMiddleware.sol";
import "../../interfaces/IAcrossMessageHandler.sol";

/// @title The middleware contract that handles Rango's receive messages from across.
/// @author George
/// @dev Note that this is not a facet and should be deployed separately.
contract RangoAcrossMiddleware is IRango, ReentrancyGuard, RangoBaseInterchainMiddleware, AcrossMessageHandler {

    /// @dev keccak256("exchange.rango.middleware.across")
    bytes32 internal constant ACROSS_MIDDLEWARE_NAMESPACE = hex"dce24b54ba6ac621127abf10d5895b3a9a9c566b24eddc36b2163fc15747e32b";

    struct RangoAcrossMiddlewareStorage {
        /// @notice Addresses that can call exec on this contract
        mapping(address => bool) whitelistedCallers;
    }

    function initAcrossMiddleware(
        address _owner,
        address[] memory _whitelistedCallers,
        address whitelistsContract
    ) external onlyOwner {
        initBaseMiddleware(_owner, whitelistsContract);
        if (_whitelistedCallers.length > 0)
            addWhitelistedCallersInternal(_whitelistedCallers);
    }

    /// Events
    /// @notice Notifies that some new caller addresses are whitelisted
    /// @param _addresses The newly whitelisted addresses
    event AcrossWhitelistedCallersAdded(address[] _addresses);

    /// @notice Notifies that some caller addresses are blacklisted
    /// @param _addresses The addresses that are removed
    event AcrossWhitelistedCallersRemoved(address[] _addresses);

    /// Only permit allowed executors
    modifier onlyWhitelistedCallers(){
        require(getRangoAcrossMiddlewareStorage().whitelistedCallers[msg.sender] == true, "not allowed");
        _;
    }

    /// External Functions
    /// @notice Adds a list of new addresses to the whitelisted across callers
    /// @param _addresses The list of callers to be whitelisted
    function addAcrossWhitelistedCallers(address[] memory _addresses) public onlyOwner {
        addWhitelistedCallersInternal(_addresses);
    }

    /// @notice Removes a list of addresses from whitelist
    /// @param _addresses The list of addresses that should be deprecated
    function removeAcrossWhitelistedCallers(address[] calldata _addresses) external onlyOwner {
        removeWhitelistedCallersInternal(_addresses);
    }

    /// @notice This function will be deprecated later and will no longer be used. TODO: Should be removed later.
    function handleAcrossMessage(
        address tokenSent,
        uint256 amount,
        bool fillCompleted,
        address relayer,
        bytes memory message
    ) external onlyWhitelistedCallers {
        if (fillCompleted == false) {
            return;
        }
        // Note: When this function is called, the caller have already sent erc20 token.
        //       This function is not called with native token, and only receives erc20 tokens (including WETH)
        Interchain.RangoInterChainMessage memory m = abi.decode((message), (Interchain.RangoInterChainMessage));
        (address receivedToken, uint dstAmount, IRango.CrossChainOperationStatus status) = LibInterchain.handleDestinationMessage(tokenSent, amount, m);

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

    function handleV3AcrossMessage(
        address tokenSent,
        uint256 amount,
        address relayer,
        bytes memory message
    ) external onlyWhitelistedCallers {
        // Note: When this function is called, the caller have already sent erc20 token.
        //       This function is not called with native token, and only receives erc20 tokens (including WETH)
        Interchain.RangoInterChainMessage memory m = abi.decode((message), (Interchain.RangoInterChainMessage));
        (address receivedToken, uint dstAmount, IRango.CrossChainOperationStatus status) = LibInterchain.handleDestinationMessage(tokenSent, amount, m);

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
    function addWhitelistedCallersInternal(address[] memory _executors) private {
        RangoAcrossMiddlewareStorage storage s = getRangoAcrossMiddlewareStorage();

        address tmpAddr;
        for (uint i = 0; i < _executors.length; i++) {
            tmpAddr = _executors[i];
            require(tmpAddr != address(0), "Invalid Executor Address");
            s.whitelistedCallers[tmpAddr] = true;
        }
        emit AcrossWhitelistedCallersAdded(_executors);
    }

    function removeWhitelistedCallersInternal(address[] calldata _executors) private {
        RangoAcrossMiddlewareStorage storage s = getRangoAcrossMiddlewareStorage();
        for (uint i = 0; i < _executors.length; i++) {
            delete s.whitelistedCallers[_executors[i]];
        }
        emit AcrossWhitelistedCallersRemoved(_executors);
    }

    /// @dev fetch local storage
    function getRangoAcrossMiddlewareStorage() private pure returns (RangoAcrossMiddlewareStorage storage s) {
        bytes32 namespace = ACROSS_MIDDLEWARE_NAMESPACE;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            s.slot := namespace
        }
    }
}