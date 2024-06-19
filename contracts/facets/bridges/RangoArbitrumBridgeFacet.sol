// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import "../../interfaces/IRango.sol";
import "../../interfaces/IRangoArbitrum.sol";
import "../../interfaces/IArbitrumBridgeInbox.sol";
import "../../interfaces/IArbitrumBridgeRouter.sol";
import "../../utils/ReentrancyGuard.sol";
import "../../libraries/LibSwapper.sol";
import "../../libraries/LibDiamond.sol";

/// @title The root contract that handles Rango's interaction with Arbitrum bridge
/// @author AMA
contract RangoArbitrumBridgeFacet is IRango, ReentrancyGuard, IRangoArbitrum {

    /// @dev keccak256("exchange.rango.facets.arbitrum")
    bytes32 internal constant ARBITRUM_NAMESPACE = hex"7d1b09bbce5c043a71c87365772180eb27aa885a0961d4a3dbf28dad7b428352";

    struct ArbitrumBridgeStorage {
        address inbox;
        address router;
    }

    /// @notice Notifies that some change(s) happened to arbitrum addresses
    /// @param oldInboxAddress The old inbox address
    /// @param oldRouterAddress The old router ddress
    /// @param newInboxAddress The newly inbox address
    /// @param newRouterAddress The newly router ddress
    event ArbitrumBridgeAddressChanged(address oldInboxAddress, address oldRouterAddress, address newInboxAddress, address newRouterAddress);

    /// @notice Notifies that arbitrum bridge started
    /// @param router The router addess
    /// @param recipient The receiver of funds
    /// @param token The input token of the bridge
    /// @param amount The amount that should be bridged
    event ArbitrumBridgeRouterCalled(address router, address recipient, address token, uint256 amount);

    /// @notice Initialize the contract.
    /// @param inboxAddress The new address of inbox
    /// @param routerAddress The new address of router
    function initArbitrum(address inboxAddress, address routerAddress) external {
        LibDiamond.enforceIsContractOwner();
        changeArbitrumAddressInternal(inboxAddress, routerAddress);
    }

    /// @notice Executes a DEX (arbitrary) call + a arbitrum bridge call
    /// @param request The general swap request containing from/to token and fee/affiliate rewards
    /// @param calls The list of DEX calls, if this list is empty, it means that there is no DEX call and we are only bridging
    /// @param bridgeRequest required data for the bridging step, including the destination chain and recipient wallet address
    function arbitrumSwapAndBridge(
        LibSwapper.SwapRequest memory request,
        LibSwapper.Call[] calldata calls,
        IRangoArbitrum.ArbitrumBridgeRequest memory bridgeRequest
    ) external payable nonReentrant {
        uint out;
        // if toToken is native coin and the user has not paid fee in msg.value,
        // then the user can pay bridge fee using output of swap.
        if (request.toToken == LibSwapper.ETH && msg.value == 0) {
            out = LibSwapper.onChainSwapsPreBridge(request, calls, 0);
            doArbitrumBridge(bridgeRequest, request.toToken, out - bridgeRequest.cost);
        }
        else {
            out = LibSwapper.onChainSwapsPreBridge(request, calls, bridgeRequest.cost);
            doArbitrumBridge(bridgeRequest, request.toToken, out);
        }        

        // event emission
        emit RangoBridgeInitiated(
            request.requestId,
            request.toToken,
            out,
            bridgeRequest.receiver,
            42161,
            false,
            false,
            uint8(BridgeType.ArbitrumBridge),
            request.dAppTag,
            request.dAppName
        );
    }

    /// @notice Executes a DEX (arbitrary) call + a arbitrum bridge call
    /// @param bridgeRequest required data for the bridging
    function arbitrumBridge(
        IRangoArbitrum.ArbitrumBridgeRequest memory request,
        RangoBridgeRequest memory bridgeRequest
    ) external payable nonReentrant {
        uint256 amountWithFee = bridgeRequest.amount + LibSwapper.sumFees(bridgeRequest);
        // transfer tokens & check inputs if necessary
        if (bridgeRequest.token == LibSwapper.ETH) {
            require(msg.value >= amountWithFee + request.cost, "Insufficient ETH sent for bridging");
        } else {
            require(msg.value >= request.cost, "Insufficient ETH sent for fee payment");
            SafeERC20.safeTransferFrom(IERC20(bridgeRequest.token), msg.sender, address(this), amountWithFee);
        }

        LibSwapper.collectFees(bridgeRequest);
        doArbitrumBridge(request, bridgeRequest.token, bridgeRequest.amount);

        // event emission
        emit RangoBridgeInitiated(
            bridgeRequest.requestId,
            bridgeRequest.token,
            bridgeRequest.amount,
            request.receiver,
            42161,
            false,
            false,
            uint8(BridgeType.ArbitrumBridge),
            bridgeRequest.dAppTag,
            bridgeRequest.dAppName
        );
    }


    /// @notice Executes a Arbitrum bridge call
    /// @param request The request object containing required field by arbitrum bridge
    /// @param fromToken The token to be bridged
    /// @param amount The amount to be bridged
    function doArbitrumBridge(
        IRangoArbitrum.ArbitrumBridgeRequest memory request,
        address fromToken,
        uint amount
    ) internal {
        ArbitrumBridgeStorage storage s = getArbitrumBridgeStorage();
        if (fromToken == LibSwapper.ETH) {
            IArbitrumBridgeInbox(s.inbox).unsafeCreateRetryableTicket{value : amount + request.cost}(
                request.receiver,
                amount,
                request.maxSubmissionCost,
                request.receiver,
                request.receiver,
                request.maxGas,
                request.maxGasPrice,
                ""
            );
            emit ArbitrumBridgeRouterCalled(s.inbox, request.receiver, fromToken, amount);
        } else {
            address gatewayAddr = IArbitrumBridgeRouter(s.router).getGateway(fromToken);
            LibSwapper.approveMax(fromToken, gatewayAddr, amount);
            IArbitrumBridgeRouter(s.router).outboundTransfer{value : request.cost}(
                fromToken,
                request.receiver,
                amount,
                request.maxGas,
                request.maxGasPrice,
                abi.encode(request.maxSubmissionCost, "")
            );
            emit ArbitrumBridgeRouterCalled(s.router, request.receiver, fromToken, amount);
        }
    }

    function changeArbitrumAddressInternal(address inboxAddress, address routerAddress) private {
        require(inboxAddress != address(0), "Invalid inbox Address");
        require(routerAddress != address(0), "Invalid router Address");
        ArbitrumBridgeStorage storage s = getArbitrumBridgeStorage();
        address oldInboxAddress = s.inbox;
        address oldRouterAddress = s.router;
        s.inbox = inboxAddress;
        s.router = routerAddress;

        emit ArbitrumBridgeAddressChanged(oldInboxAddress, oldRouterAddress, inboxAddress, routerAddress);
    }

    /// @dev fetch local storage
    function getArbitrumBridgeStorage() private pure returns (ArbitrumBridgeStorage storage s) {
        bytes32 namespace = ARBITRUM_NAMESPACE;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            s.slot := namespace
        }
    }
}