// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.16;

import "../../interfaces/IWETH.sol";
import "../../interfaces/IRangoSymbiosis.sol";
import "../../interfaces/ISymbiosisMetaRouter.sol";
import "../../interfaces/IUniswapV2.sol";
import "../../interfaces/IRangoMessageReceiver.sol";
import "../../interfaces/IRango.sol";
import "../../interfaces/Interchain.sol";
import "../../libraries/LibInterchain.sol";
import "../../libraries/LibDiamond.sol";
import "../../utils/ReentrancyGuard.sol";


/// @title The root contract that handles Rango's interaction with symbiosis
/// @author Rza
contract RangoSymbiosisFacet is IRango, ReentrancyGuard, IRangoSymbiosis {
    /// Storage ///
    /// @dev keccak256("exchange.rango.facets.symbiosis")
    bytes32 internal constant SYMBIOSIS_NAMESPACE = hex"81ce8a65cc4e11b9c999b4c5d66459bb20272ba6288f99768bc4d0cb2c8ca95d";

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

    /// @notice Initialize the contract.
    /// @param addresses addresses of Symbiosis routers
    function initSymbiosis(SymbiosisStorage calldata addresses) external {
        LibDiamond.enforceIsContractOwner();
        updateSymbiosisAddressInternal(addresses.symbiosisMetaRouter, addresses.symbiosisMetaRouterGateway);
    }

    /// @notice Executes a DEX call + a Symbiosis bridge call + a Dex call
    /// @param request The general swap request containing from/to token and fee/affiliate rewards
    /// @param calls The list of DEX calls, if this list is empty, it means that there is no DEX call and we are only bridging
    /// @param bridgeRequest required data for the bridging step, including the destination chain and recipient wallet address
    function symbiosisSwapAndBridge(
        LibSwapper.SwapRequest memory request,
        LibSwapper.Call[] calldata calls,
        IRangoSymbiosis.SymbiosisBridgeRequest calldata bridgeRequest
    ) external payable nonReentrant {
        uint out = LibSwapper.onChainSwapsPreBridge(request, calls, 0);
        doSymbiosisBridge(bridgeRequest, request.toToken, out);

        // event emission
        emit RangoBridgeInitiated(
            request.requestId,
            request.toToken,
            out,
            bridgeRequest.receiver,
            bridgeRequest.toChainId,
            false,
            false,
            uint8(BridgeType.Symbiosis),
            request.dAppTag
        );
    }

    function symbiosisBridge(
        IRangoSymbiosis.SymbiosisBridgeRequest calldata symbiosisRequest,
        IRango.RangoBridgeRequest memory bridgeRequest
    ) external payable nonReentrant {
        SymbiosisStorage storage s = getSymbiosisStorage();
        uint256 amountWithFee = bridgeRequest.amount + LibSwapper.sumFees(bridgeRequest);
        // transfer tokens if necessary
        if (bridgeRequest.token == LibSwapper.ETH) {
            require(msg.value >= amountWithFee, "Insufficient ETH sent for bridging");
        } else {
            SafeERC20.safeTransferFrom(IERC20(bridgeRequest.token), msg.sender, address(this), amountWithFee);
        }

        LibSwapper.collectFees(bridgeRequest);
        doSymbiosisBridge(symbiosisRequest, bridgeRequest.token, bridgeRequest.amount);

        // event emission
        emit RangoBridgeInitiated(
            bridgeRequest.requestId,
            bridgeRequest.token,
            bridgeRequest.amount,
            symbiosisRequest.receiver,
            symbiosisRequest.toChainId,
            false,
            false,
            uint8(BridgeType.Symbiosis),
            bridgeRequest.dAppTag
        );
    }

    /// @notice Executes a bridging via symbiosis
    /// @param request The extra fields required by the symbiosis bridge
    /// @param token The requested token to bridge
    /// @param amount The requested amount to bridge
    function doSymbiosisBridge(
        SymbiosisBridgeRequest calldata request,
        address token,
        uint256 amount
    ) internal {
        SymbiosisStorage storage s = getSymbiosisStorage();
        require(s.symbiosisMetaRouter != LibSwapper.ETH, 'Symbiosis meta router address not set');
        require(s.symbiosisMetaRouterGateway != LibSwapper.ETH, 'Symbiosis meta router gateway address not set');
        require(token != LibSwapper.ETH, 'Symbiosis contract handles only ERC20 tokens');
        LibSwapper.approveMax(token, s.symbiosisMetaRouterGateway, amount);

        MetaRouteTransaction memory transactionData = request.metaRouteTransaction;
        bytes4 sig = bytes4(request.metaRouteTransaction.otherSideCalldata[:4]);
        // for further insight into othersideCalldata please refer to symbiosis sdk
        // https://github.com/symbiosis-finance/js-sdk/blob/v2/src/crosschain/baseSwapping.ts#L462
        // https://github.com/symbiosis-finance/js-sdk/blob/v2/src/crosschain/baseSwapping.ts#L426
        // https://github.com/symbiosis-finance/js-sdk/blob/v2/src/crosschain/baseSwapping.ts#L395

        if (request.bridgeType == SymbiosisBridgeType.META_BURN) {
            // metaBurnSyntheticToken((uint256,uint256,address,address,address,bytes,uint256,address,address,address,address,uint256,bytes32))
            bytes4 burnSig = hex"e691a2aa";
            require(sig == burnSig, 'UnAuthorized! Invalid otherSideCalldata');
            MetaBurnTransaction memory decodedMetaBurnTx = abi.decode(request.metaRouteTransaction.otherSideCalldata[4:], (MetaBurnTransaction));
            require(token == decodedMetaBurnTx.sToken, 'Invalid Token');
            require(request.receiver == decodedMetaBurnTx.chain2address, 'Invalid Requst!');
        } else {
            // metaSynthesize((uint256,uint256,address,address,address,address,address,uint256,address[],address,bytes,address,bytes,uint256,address,bytes32))
            bytes4 synthSig = hex"ce654c17";
            require(sig == synthSig, 'UnAuthorized! Invalid otherSideCalldata');
            MetaSynthesizeTransaction memory decodedMetaSynthTx = abi.decode(request.metaRouteTransaction.otherSideCalldata[4:], (MetaSynthesizeTransaction));
            require(token == decodedMetaSynthTx.rToken, 'Invalid Token');
            require(request.receiver == decodedMetaSynthTx.chain2address, 'Invalid Requst!');
        }
        transactionData.amount = amount;

        ISymbiosisMetaRouter(s.symbiosisMetaRouter).metaRoute(transactionData);
    }

    function updateSymbiosisAddressInternal(address metaRouter, address metaRouterGateway) private {
        require(metaRouter != address(0), "Invalid metaRouter Address");
        require(metaRouterGateway != address(0), "Invalid metaRouterGateway Address");
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
