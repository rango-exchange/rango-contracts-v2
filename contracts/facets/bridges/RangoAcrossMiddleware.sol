// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.16;

import "../../libraries/LibInterchain.sol";
import "../../utils/ReentrancyGuard.sol";
import "../base/RangoBaseInterchainMiddleware.sol";
import "../../interfaces/IAcrossMessageHandler.sol";
import "../../interfaces/IAcrossSpokePool.sol";

/// @title The middleware contract that handles Rango's receive messages from acrs.
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
        address _weth,
        address[] memory _whitelistedCallers
    ) external onlyOwner {
        initBaseMiddleware(_owner, address(0), _weth);
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

    function handleAcrossMessage(
        address tokenSent,
        uint256 amount,
        bytes memory message
    ) external payable onlyWhitelistedCallers {
        // Note: When this function is called, the caller have already sent erc20 token or native token to this contract.
        //       When this function is called with native token, msg.value is zero because the ETH is received in a previous transfer.
        //       If we have received native token, the tokenSent parameter will be WETH address, not address(0).

        Interchain.RangoInterChainMessage memory m = abi.decode((message), (Interchain.RangoInterChainMessage));
        address token = tokenSent;

        if (tokenSent == IAcrossSpokePool(msg.sender).wrappedNativeToken()) {
            token = address(0);
        }

        (address receivedToken, uint dstAmount, IRango.CrossChainOperationStatus status) = LibInterchain.handleDestinationMessage(token, amount, m);

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