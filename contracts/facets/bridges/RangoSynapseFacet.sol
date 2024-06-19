// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import "../../interfaces/ISynapseRouter.sol";
import "../../interfaces/IRangoSynapse.sol";
import "../../interfaces/IRango.sol";
import "../../utils/ReentrancyGuard.sol";
import "../../libraries/LibSwapper.sol";
import "../../libraries/LibDiamond.sol";
import "../../libraries/LibPausable.sol";

/// @title The root contract that handles Rango's interaction with Synapse bridge
/// @author Rango DeXter
contract RangoSynapseFacet is IRango, ReentrancyGuard, IRangoSynapse {
    /// Storage ///
    bytes32 internal constant SYNAPSE_NAMESPACE = keccak256("exchange.rango.facets.synapse");

    struct SynapseStorage {
        /// @notice Synapse router address in the current chain
        address routerAddress;
    }

    /// @notice Initialize the contract.
    /// @param _address Synapse router contract address
    function initSynapse(address _address) external {
        LibDiamond.enforceIsContractOwner();
        updateSynapseRoutersInternal(_address);
    }

    /// @notice Emits when the synapse address is updated
    /// @param _oldAddress The previous address
    /// @param _newAddress The new address
    event SynapseAddressUpdated(address _oldAddress, address _newAddress);

    /// @notice Enables the contract to receive native ETH token from other contracts including WETH contract
    receive() external payable {}

    /// @notice Executes a DEX (arbitrary) call + a Synapse bridge call
    /// @param request The general swap request containing from/to token and fee/affiliate rewards
    /// @param calls The list of DEX calls, if this list is empty, it means that there is no DEX call and we are only bridging
    /// @param bridgeRequest required data for the bridging step, including the destination chain and recipient wallet address
    function synapseSwapAndBridge(
        LibSwapper.SwapRequest memory request,
        LibSwapper.Call[] calldata calls,
        IRangoSynapse.SynapseBridgeRequest memory bridgeRequest
    ) external payable nonReentrant {
        LibPausable.enforceNotPaused();
        uint out = LibSwapper.onChainSwapsPreBridge(request, calls, 0);
        doSynapseBridge(bridgeRequest, request.toToken, out);
        emit RangoBridgeInitiated(
            request.requestId,
            request.toToken,
            out,
            bridgeRequest.to,
            bridgeRequest.chainId,
            false,
            false,
            uint8(BridgeType.Synapse),
            request.dAppTag,
            request.dAppName
        );
    }

    /// @notice Executes a Synapse bridge call
    /// @param request The fields required by synapse bridge
    function synapseBridge(
        IRangoSynapse.SynapseBridgeRequest memory request,
        RangoBridgeRequest memory bridgeRequest
    ) external payable nonReentrant {
        LibPausable.enforceNotPaused();
        uint amount = bridgeRequest.amount;
        address token = bridgeRequest.token;
        uint amountWithFee = amount + LibSwapper.sumFees(bridgeRequest);
        // transfer tokens if necessary
        if (token != LibSwapper.ETH) {
            SafeERC20.safeTransferFrom(IERC20(token), msg.sender, address(this), amountWithFee);
        } else {
            require(msg.value >= amountWithFee);
        }
        LibSwapper.collectFees(bridgeRequest);
        doSynapseBridge(request, token, amount);

        emit RangoBridgeInitiated(
            bridgeRequest.requestId,
            token,
            amount,
            request.to,
            request.chainId,
            false,
            false,
            uint8(BridgeType.Synapse),
            bridgeRequest.dAppTag,
            bridgeRequest.dAppName
        );
    }

    /// @notice Executes a Synapse bridge call
    /// @param request required data for bridge
    /// @param inputAmount The amount of the token to be bridged
    function doSynapseBridge(
        SynapseBridgeRequest memory request,
        address token,
        uint inputAmount
    ) internal {
        SynapseStorage storage s = getSynapseStorage();
        require(s.routerAddress == request.router, 'Requested router address not whitelisted');
        require(request.to != LibSwapper.ETH, "Invalid recipient address");
        require(request.chainId != 0, "Invalid recipient chain");
        require(inputAmount > 0, "Invalid amount");

        if (token != LibSwapper.ETH) {
            LibSwapper.approveMax(token, request.router, inputAmount);
        }

        ISynapseRouter router = ISynapseRouter(request.router);

        if (request.bridgeType == SynapseBridgeType.SWAP_AND_REDEEM)
            synapseSwapAndRedeem(router, request, inputAmount);
        else if (request.bridgeType == SynapseBridgeType.SWAP_AND_REDEEM_AND_SWAP)
            synapseSwapAndRedeemAndSwap(router, request, inputAmount);
        else if (request.bridgeType == SynapseBridgeType.SWAP_AND_REDEEM_AND_REMOVE)
            synapseSwapAndRedeemAndRemove(router, request, inputAmount);
        else if (request.bridgeType == SynapseBridgeType.REDEEM)
            synapseRedeem(router, request, inputAmount);
        else if (request.bridgeType == SynapseBridgeType.REDEEM_AND_SWAP)
            synapseRedeemAndSwap(router, request, inputAmount);
        else if (request.bridgeType == SynapseBridgeType.REDEEM_AND_REMOVE)
            synapseRedeemAndRemove(router, request, inputAmount);
        else if (request.bridgeType == SynapseBridgeType.DEPOSIT)
            synapseDeposit(router, request, inputAmount);
        else if (request.bridgeType == SynapseBridgeType.DEPOSIT_ETH)
            synapseDepositETH(router, request, inputAmount);
        else if (request.bridgeType == SynapseBridgeType.DEPOSIT_ETH_AND_SWAP)
            synapseDepositETHAndSwap(router, request, inputAmount);
        else if (request.bridgeType == SynapseBridgeType.DEPOSIT_AND_SWAP)
            synapseDepositAndSwap(router, request, inputAmount);
        else if (request.bridgeType == SynapseBridgeType.SWAP_ETH_AND_REDEEM)
            synapseSwapETHAndRedeem(router, request, inputAmount);
        else if (request.bridgeType == SynapseBridgeType.ZAP_AND_DEPOSIT)
            synapseZapAndDeposit(router, request, inputAmount);
        else if (request.bridgeType == SynapseBridgeType.ZAP_AND_DEPOSIT_AND_SWAP)
            synapseZapAndDepositAndSwap(router, request, inputAmount);
        else
            revert("Invalid bridge type");

        emit SynapseBridgeDetailEvent(
            request.bridgeToken, request.tokenIndexFrom, request.tokenIndexTo, request.minDy, request.deadline,
            request.swapTokenIndexFrom, request.swapTokenIndexTo, request.swapMinDy, request.swapDeadline
        );

    }

    function synapseDeposit(ISynapseRouter router, SynapseBridgeRequest memory request, uint inputAmount) private {
        router.deposit(request.to, request.chainId, IERC20(request.bridgeToken), inputAmount);
    }

    function synapseRedeem(ISynapseRouter router, SynapseBridgeRequest memory request, uint inputAmount) private {
        router.redeem(request.to, request.chainId, IERC20(request.bridgeToken), inputAmount);
    }

    function synapseDepositAndSwap(ISynapseRouter router, SynapseBridgeRequest memory request, uint inputAmount) private {
        router.depositAndSwap(
            request.to, request.chainId, IERC20(request.bridgeToken), inputAmount, request.tokenIndexFrom,
            request.tokenIndexTo, request.minDy, request.deadline
        );
    }

    function synapseDepositETH(ISynapseRouter router, SynapseBridgeRequest memory request, uint inputAmount) private {
        router.depositETH{value : inputAmount}(request.to, request.chainId, inputAmount);
    }

    function synapseDepositETHAndSwap(ISynapseRouter router, SynapseBridgeRequest memory request, uint inputAmount) private {
        router.depositETHAndSwap{value : inputAmount}(
            request.to, request.chainId, inputAmount, request.tokenIndexFrom, request.tokenIndexTo, request.minDy,
            request.deadline
        );
    }

    function synapseRedeemAndSwap(ISynapseRouter router, SynapseBridgeRequest memory request, uint inputAmount) private {
        router.redeemAndSwap(
            request.to, request.chainId, IERC20(request.bridgeToken), inputAmount, request.tokenIndexFrom,
            request.tokenIndexTo, request.minDy, request.deadline
        );
    }

    function synapseRedeemAndRemove(ISynapseRouter router, SynapseBridgeRequest memory request, uint inputAmount) private {
        router.redeemAndRemove(
            request.to, request.chainId, IERC20(request.bridgeToken), inputAmount, request.tokenIndexFrom,
            request.minDy, request.deadline
        );
    }

    function synapseSwapAndRedeem(ISynapseRouter router, SynapseBridgeRequest memory request, uint inputAmount) private {
        router.swapAndRedeem(
            request.to, request.chainId, IERC20(request.bridgeToken), request.tokenIndexFrom,
            request.tokenIndexTo, inputAmount, request.minDy, request.deadline
        );
    }

    function synapseSwapETHAndRedeem(ISynapseRouter router, SynapseBridgeRequest memory request, uint inputAmount) private {
        router.swapETHAndRedeem{value : inputAmount}(
            request.to, request.chainId, IERC20(request.bridgeToken), request.tokenIndexFrom, request.tokenIndexTo,
            inputAmount, request.minDy, request.deadline
        );
    }

    function synapseSwapAndRedeemAndSwap(ISynapseRouter router, SynapseBridgeRequest memory request, uint inputAmount) private {
        router.swapAndRedeemAndSwap(
            request.to, request.chainId, IERC20(request.bridgeToken), request.tokenIndexFrom, request.tokenIndexTo,
            inputAmount, request.minDy, request.deadline, request.swapTokenIndexFrom, request.swapTokenIndexTo,
            request.swapMinDy, request.swapDeadline
        );
    }

    function synapseSwapAndRedeemAndRemove(ISynapseRouter router, SynapseBridgeRequest memory request, uint inputAmount) private {
        router.swapAndRedeemAndRemove(
            request.to, request.chainId, IERC20(request.bridgeToken), request.tokenIndexFrom, request.tokenIndexTo,
            inputAmount, request.minDy, request.deadline, request.swapTokenIndexFrom, request.minDy,
            request.swapDeadline
        );
    }

    function synapseZapAndDeposit(ISynapseRouter router, SynapseBridgeRequest memory request, uint inputAmount) private {
        router.zapAndDeposit(
            request.to, request.chainId, IERC20(request.bridgeToken), request.liquidityAmounts, request.minDy,
            request.deadline
        );
    }

    function synapseZapAndDepositAndSwap(ISynapseRouter router, SynapseBridgeRequest memory request, uint inputAmount) private {
        router.zapAndDepositAndSwap(
            request.to, request.chainId, IERC20(request.bridgeToken), request.liquidityAmounts, request.minDy,
            request.deadline, request.tokenIndexFrom, request.tokenIndexTo, request.swapMinDy, request.swapDeadline
        );
    }

    function updateSynapseRoutersInternal(address _address) private {
        require(_address != address(0), "Invalid Synapse Address");
        SynapseStorage storage s = getSynapseStorage();
        address oldAddress = s.routerAddress;
        s.routerAddress = _address;

        emit SynapseAddressUpdated(oldAddress, _address);
    }

    /// @dev fetch local storage
    function getSynapseStorage() private pure returns (SynapseStorage storage s) {
        bytes32 namespace = SYNAPSE_NAMESPACE;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            s.slot := namespace
        }
    }
}
