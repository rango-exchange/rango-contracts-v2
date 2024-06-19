// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import "../../interfaces/IRango.sol";
import "../../interfaces/IAxelarExecutable.sol";
import "../../interfaces/IUniswapV2.sol";
import "../../interfaces/IRangoMessageReceiver.sol";
import "../../interfaces/Interchain.sol";
import "../../libraries/LibInterchain.sol";
import "../base/RangoBaseInterchainMiddleware.sol";
import "../../utils/ReentrancyGuard.sol";

/// @title The contract that receives interchain messages
/// @author AMA
/// @dev This is not a facet and is deployed separate from diamond.
contract RangoSymbiosisMiddleware is IRango, ReentrancyGuard, RangoBaseInterchainMiddleware {
    /// Storage ///
    bytes32 internal constant SYMBIOSIS_NAMESPACE = keccak256("exchange.rango.middleware.symbiosis");

    function initSymbiosisMiddleware(
        address _owner,
        address _gatewayAddress,
        address _routerAddress,
        address whitelistsContract
    ) external onlyOwner {
        initBaseMiddleware(_owner, whitelistsContract);
        updateSymbiosisGatewayInternal(_routerAddress, _gatewayAddress);
    }

    struct SymbiosisStorage {
        /// @notice The address of symbiosis meta router contract
        address symbiosisMetaRouter;
        /// @notice The address of symbiosis meta router gateway contract
        address symbiosisMetaRouterGateway;
    }

    /// @notice Emits when the symbiosis contracts address is updated
    /// @param oldMetaRouter The previous address for MetaRouter contract
    /// @param oldMetaRouterGateway The previous address for MetaRouterGateway contract
    /// @param newMetaRouter The updated address for MetaRouter contract
    /// @param newMetaRouterGateway The updated address for MetaRouterGateway contract
    event SymbiosisAddressUpdated(
        address oldMetaRouter,
        address oldMetaRouterGateway,
        address indexed newMetaRouter,
        address indexed newMetaRouterGateway
    );

    /// @notice A series of events with different status value to help us track the progress of cross-chain swap
    /// @param token The token address in the current network that is being bridged
    /// @param outputAmount The latest observed amount in the path, aka: input amount for source and output amount on dest
    /// @param status The latest status of the overall flow
    /// @param source The source address that initiated the transaction
    /// @param destination The destination address that received the money, ZERO address if not sent to the end-user yet
    event SymbiosisSwapStatusUpdated(
        address token,
        uint256 outputAmount,
        IRango.CrossChainOperationStatus status,
        address source,
        address destination
    );

    function updateSymbiosisGatewayAddress(address metaRouter, address metaRouterGateway) public onlyOwner {
        updateSymbiosisGatewayInternal(metaRouter, metaRouterGateway);
    }

    function fetchTokenFromRouterAndRefund(
        address _tokenAddress,
        uint256 _amount,
        address _refundReceiver
    ) external onlyOwner {
        address refundAddr = _refundReceiver == LibSwapper.ETH ? msg.sender : _refundReceiver;
        IERC20 ercToken = IERC20(_tokenAddress);
        SafeERC20.safeTransferFrom(ercToken, getSymbiosisStorage().symbiosisMetaRouter, refundAddr, _amount);
        emit Refunded(_tokenAddress, _amount);
    }

    /// @notice Complete bridge in destination chain
    /// @param amount The requested amount to bridge
    /// @param token The received token after bridge
    /// @param receivedMessage imMessage to send in destination chain
    function messageReceive(
        uint256 amount,
        address token,
        Interchain.RangoInterChainMessage memory receivedMessage
    ) external payable nonReentrant {
        require(msg.sender == getSymbiosisStorage().symbiosisMetaRouter, "not meta router");
        SafeERC20.safeTransferFrom(IERC20(token), msg.sender, address(this), amount);
        (address receivedToken, uint dstAmount, IRango.CrossChainOperationStatus status) = LibInterchain.handleDestinationMessage(token, amount, receivedMessage);

        emit SymbiosisSwapStatusUpdated(receivedToken, dstAmount, status, receivedMessage.originalSender, receivedMessage.recipient);
    }

    function updateSymbiosisGatewayInternal(address metaRouter, address metaRouterGateway) private {
        require(metaRouter != LibSwapper.ETH, "Invalid metaRouter address");
        require(metaRouterGateway != LibSwapper.ETH, "Invalid metaRouterGateway address");
        SymbiosisStorage storage s = getSymbiosisStorage();
        address oldMetaRouter = s.symbiosisMetaRouter;
        address oldMetaRouterGateway = s.symbiosisMetaRouterGateway;
        s.symbiosisMetaRouter = metaRouter;
        s.symbiosisMetaRouterGateway = metaRouterGateway;
        emit SymbiosisAddressUpdated(oldMetaRouter, oldMetaRouterGateway, metaRouter, metaRouterGateway);
    }

    /// @dev fetch local storage
    function getSymbiosisStorage() private pure returns (SymbiosisStorage storage s) {
        bytes32 namespace = SYMBIOSIS_NAMESPACE;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            s.slot := namespace
        }
    }
}