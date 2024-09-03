// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import "../../../interfaces/IThorchainRouter.sol";
import "../../../interfaces/IRangoThorchain.sol";
import "../../../interfaces/IRango.sol";
import "../../../libraries/LibSwapper.sol";
import "../../../utils/ReentrancyGuard.sol";
import "../../../libraries/LibPausable.sol";

/// @title A contract to handle interactions with Thorchain Router contract on evm chains.
/// @author Thinking Particle
/// @notice This facet interacts with thorchain router.
/// @dev This contract checks for basic validation and also checks that provided thorchain router is whitelisted.
contract RangoThorchainFacet is IRango, IRangoThorchain, ReentrancyGuard {
    /// @notice emitted to notify that a swap to thorchain has been initiated by rango and provides the parameters used for the swap.
    /// @param vault The vault address of Thorchain. This cannot be hardcoded because Thorchain rotates vaults.
    /// @param token The token contract address (if token is native, should be 0x0000000000000000000000000000000000000000)
    /// @param amount The amount of token to be swapped. It should be positive and if token is native, msg.value should be bigger than amount.
    /// @param memo The transaction memo used by Thorchain which contains the thorchain swap data. More info: https://dev.thorchain.org
    /// @param expiration The expiration block number. If the tx is included after this block, it will be reverted.
    event ThorchainTxInitiated(address vault, address token, uint amount, string memo, uint expiration);

    /// @notice Swap tokens if necessary, then pass it to RangoThorchain
    /// @dev Swap tokens if necessary, then pass it to RangoThorchain. If no swap is required (calls.length==0) the provided token is passed to RangoThorchain without change.
    /// @param request The swap information used to check input and output token addresses and balances, as well as the fees if any. Together with calls param, determines the swap logic before passing to Thorchain.
    /// @param calls The contract call data that is used to swap (can be empty if no swap is needed). Together with request param, determines the swap logic before passing to Thorchain.
    /// @param bridgeRequest The required data to bridge with thorchain
    function thorchainSwapAndBridge(
        LibSwapper.SwapRequest memory request,
        LibSwapper.Call[] calldata calls,
        ThorchainBridgeRequest memory bridgeRequest
    ) external payable nonReentrant {
        LibPausable.enforceNotPaused();
        uint out = LibSwapper.onChainSwapsPreBridge(request, calls, 0);
        if (request.toToken != LibSwapper.ETH) {
            LibSwapper.approveMax(request.toToken, bridgeRequest.tcRouter, out);
        }

        doSwapInToThorchain(
            bridgeRequest,
            request.toToken,
            out
        );
        // event emission
        emit RangoBridgeInitiated(
            request.requestId,
            request.toToken,
            out,
            LibSwapper.ETH,// receiver is embedded in data and we dont extract it for event emission
            0,
            false,
            false,
            uint8(BridgeType.Thorchain),
            request.dAppTag,
            request.dAppName
        );
    }

    /// @notice Do a swap through thorchain
    /// @param bridgeRequest The necessary data for bridging
    /// @param request The required data to bridge with thorchain
    function thorchainBridge(
        RangoBridgeRequest memory bridgeRequest,
        ThorchainBridgeRequest memory request
    ) external payable nonReentrant {
        LibPausable.enforceNotPaused();
        uint amount = bridgeRequest.amount;
        uint amountWithFee = amount + LibSwapper.sumFees(bridgeRequest);
        address token = bridgeRequest.token;
        if (token == LibSwapper.ETH) {
            require(msg.value >= amountWithFee, "insufficient ETH sent");
        } else {
            SafeERC20.safeTransferFrom(IERC20(token), msg.sender, address(this), amountWithFee);
            LibSwapper.approveMax(token, request.tcRouter, amount);
        }
        LibSwapper.collectFees(bridgeRequest);

        doSwapInToThorchain(
            request,
            token,
            amount
        );

        // event emission
        emit RangoBridgeInitiated(
            bridgeRequest.requestId,
            token,
            amount,
            LibSwapper.ETH,// receiver is embedded in memo and we dont extract it for event emission
            0,
            false,
            false,
            uint8(BridgeType.Thorchain),
            bridgeRequest.dAppTag,
            bridgeRequest.dAppName
        );
    }

    /// @notice Defines parameters used for swapIn functionality on thorchain router.
    /// @param request The required data to bridge with thorchain
    /// @param token The token contract address (if token is native, should be 0x0000000000000000000000000000000000000000)
    /// @param amount The amount of token to be swapped. It should be positive and if token is native, msg.value should be bigger than amount.
    function doSwapInToThorchain(
        ThorchainBridgeRequest memory request,
        address token,
        uint amount
    ) internal {
        LibSwapper.BaseSwapperStorage storage baseStorage = LibSwapper.getBaseSwapperStorage();
        require(baseStorage.whitelistContracts[request.tcRouter], "thorchain router not whitelisted");

        if (request.preventNonEoaSender) {
            if (msg.sender.code.length != 0) {
                revert("Sender is not EOA");
            }
        }

        IThorchainRouter(request.tcRouter).depositWithExpiry{value : token == LibSwapper.ETH ? amount : 0}(
            payable(request.tcVault), // address payable vault,
            token, // address asset,
            amount, // uint amount,
            request.thorchainMemo, // string calldata memo,
            request.expiration  // uint expiration) external payable;
        );
        emit ThorchainTxInitiated(request.tcVault, token, amount, request.thorchainMemo, request.expiration);
    }

}