// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import "../../libraries/LibInterchain.sol";
import "../../utils/ReentrancyGuard.sol";
import "../base/RangoBaseInterchainMiddleware.sol";
import "../../interfaces/IChainFlipMessageHandler.sol";

/// @title The middleware contract that handles Rango's receive messages from chainflip.
/// @author Smnp
/// @dev Note that this is not a facet and should be deployed separately.
contract RangoChainFlipMiddleware is IRango, ReentrancyGuard, RangoBaseInterchainMiddleware, IChainFlipMessageHandler {
    /// Storage ///
    bytes32 internal constant CHAINFLIP_MIDDLEWARE_NAMESPACE = keccak256("exchange.rango.middleware.chainflip");

    struct RangoChainFlipMiddlewareStorage {
        /// @notice Addresses that can call exec on this contract
        mapping(address => bool) whitelistedCallers;
    }

    function initChainFlipMiddleware(
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
    event ChainFlipWhitelistedCallersAdded(address[] _addresses);

    /// @notice Notifies that some caller addresses are blacklisted
    /// @param _addresses The addresses that are removed
    event ChainFlipWhitelistedCallersRemoved(address[] _addresses);

    /// Only permit allowed executors
    modifier onlyWhitelistedCallers(){
        require(getRangoChainFlipMiddlewareStorage().whitelistedCallers[msg.sender] == true, "not allowed");
        _;
    }

    /// External Functions
    /// @notice Adds a list of new addresses to the whitelisted ChainFlip callers
    /// @param _addresses The list of callers to be whitelisted
    function addChainFlipWhitelistedCallers(address[] memory _addresses) public onlyOwner {
        addWhitelistedCallersInternal(_addresses);
    }

    /// @notice Removes a list of addresses from whitelist
    /// @param _addresses The list of addresses that should be deprecated
    function removeChainFlipWhitelistedCallers(address[] calldata _addresses) external onlyOwner {
        removeWhitelistedCallersInternal(_addresses);
    }

    function cfReceive(
        uint32 srcChain,
        bytes calldata srcAddress,
        bytes calldata message,
        address token,
        uint256 amount
    ) external payable onlyWhitelistedCallers onlyWhenNotPaused nonReentrant{
        Interchain.RangoInterChainMessage memory m = abi.decode((message), (Interchain.RangoInterChainMessage));
        if(token == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE){
            token = address(0);
        }
        (address receivedToken, uint dstAmount, IRango.CrossChainOperationStatus status) = LibInterchain.handleDestinationMessage(
            token, // this should be address(0) for native 
            amount, 
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

    /// Private and Internal
    function addWhitelistedCallersInternal(address[] memory _executors) private {
        RangoChainFlipMiddlewareStorage storage s = getRangoChainFlipMiddlewareStorage();

        address tmpAddr;
        for (uint i = 0; i < _executors.length; i++) {
            tmpAddr = _executors[i];
            require(tmpAddr != address(0), "Invalid Executor Address");
            s.whitelistedCallers[tmpAddr] = true;
        }
        emit ChainFlipWhitelistedCallersAdded(_executors);
    }

    function removeWhitelistedCallersInternal(address[] calldata _executors) private {
        RangoChainFlipMiddlewareStorage storage s = getRangoChainFlipMiddlewareStorage();
        for (uint i = 0; i < _executors.length; i++) {
            delete s.whitelistedCallers[_executors[i]];
        }
        emit ChainFlipWhitelistedCallersRemoved(_executors);
    }

    /// @dev fetch local storage
    function getRangoChainFlipMiddlewareStorage() private pure returns (RangoChainFlipMiddlewareStorage storage s) {
        bytes32 namespace = CHAINFLIP_MIDDLEWARE_NAMESPACE;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            s.slot := namespace
        }
    }
}