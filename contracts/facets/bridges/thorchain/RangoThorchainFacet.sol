// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.16;

import "../../../interfaces/IThorchainRouter.sol";
import "../../../interfaces/IRangoThorchain.sol";
import "../../../interfaces/IRango.sol";
import "../../../libraries/LibSwapper.sol";
import "../../../utils/ReentrancyGuard.sol";

/// @title A contract to handle interactions with Thorchain Router contract on evm chains.
/// @author Thinking Particle
/// @notice This facet interacts with thorchain router.
/// @dev This contract checks for basic validation and also checks that provided thorchain router is whitelisted.
contract RangoThorchainFacet is IRango, IRangoThorchain, ReentrancyGuard {
    /// @notice emitted to notify that a swap to thorchain has been initiated by rango and provides the parameters used for the swap.
    /// @param vault The vault address of Thorchain. This cannot be hardcoded because Thorchain rotates vaults.
    /// @param token The token contract address (if token is native, should be 0x0000000000000000000000000000000000000000)
    /// @param amount The amount of token to be swapped. It should be positive and if token is native, msg.value should be bigger than amount.
    /// @param memo The transaction memo used by Thorchain which contains the thorchain swap data. More info: https://dev.thorchain.org/thorchain-dev/memos
    /// @param expiration The expiration block number. If the tx is included after this block, it will be reverted.
    event ThorchainTxInitiated(address vault, address token, uint amount, string memo, uint expiration);

    receive() external payable {}

    /// @notice Swap tokens if necessary, then pass it to RangoThorchain
    /// @dev Swap tokens if necessary, then pass it to RangoThorchain. If no swap is required (calls.length==0) the provided token is passed to RangoThorchain without change.
    /// @param request The swap information used to check input and output token addresses and balances, as well as the fees if any. Together with calls param, determines the swap logic before passing to Thorchain.
    /// @param calls The contract call data that is used to swap (can be empty if no swap is needed). Together with request param, determines the swap logic before passing to Thorchain.
    /// @param tcRouter The router contract address of Thorchain. This cannot be hardcoded because Thorchain can upgrade its router and the address might change.
    /// @param tcVault The vault address of Thorchain. This cannot be hardcoded because Thorchain rotates vaults.
    /// @param thorchainMemo The transaction memo used by Thorchain which contains the thorchain swap data. More info: https://dev.thorchain.org/thorchain-dev/memos
    /// @param expiration The expiration block number. If the tx is included after this block, it will be reverted.
    function thorchainSwapAndBridge(
        LibSwapper.SwapRequest memory request,
        LibSwapper.Call[] calldata calls,
        address tcRouter,
        address tcVault,
        string calldata thorchainMemo,
        uint expiration
    ) external payable nonReentrant {
        uint out = LibSwapper.onChainSwapsPreBridge(request, calls, 0);
        if (request.toToken != LibSwapper.ETH) {
            LibSwapper.approve(request.toToken, tcRouter, out);
        }

        doSwapInToThorchain(
            request.toToken,
            out,
            tcRouter,
            tcVault,
            thorchainMemo,
            expiration
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
            request.dAppTag
        );
    }

    /// @notice Do a swap through thorchain
    /// @param request The necessary data for bridging
    /// @param tcRouter The router contract address of Thorchain. This cannot be hardcoded because Thorchain can upgrade its router and the address might change.
    /// @param tcVault The vault address of Thorchain. This cannot be hardcoded because Thorchain rotates vaults.
    /// @param thorchainMemo The transaction memo used by Thorchain which contains the thorchain swap data. More info: https://dev.thorchain.org/thorchain-dev/memos
    /// @param expiration The expiration block number. If the tx is included after this block, it will be reverted.
    function thorchainBridge(
        RangoBridgeRequest memory request,
        address tcRouter,
        address tcVault,
        string calldata thorchainMemo,
        uint expiration
    ) external payable nonReentrant {
        uint amount = request.amount;
        uint amountWithFee = amount + LibSwapper.sumFees(request);
        address token = request.token;
        if (token == LibSwapper.ETH) {
            require(msg.value >= amountWithFee, "insufficient ETH sent");
        } else {
            SafeERC20.safeTransferFrom(IERC20(token), msg.sender, address(this), amountWithFee);
            LibSwapper.approve(token, tcRouter, amount);
        }
        LibSwapper.collectFees(request);

        doSwapInToThorchain(
            token,
            amount,
            tcRouter,
            tcVault,
            thorchainMemo,
            expiration
        );

        // event emission
        emit RangoBridgeInitiated(
            request.requestId,
            token,
            amount,
            LibSwapper.ETH,// receiver is embedded in memo and we dont extract it for event emission
            0,
            false,
            false,
            uint8(BridgeType.Thorchain),
            request.dAppTag
        );
    }

    /// @notice Defines parameters used for swapIn functionality on thorchain router.
    /// @param token The token contract address (if token is native, should be 0x0000000000000000000000000000000000000000)
    /// @param amount The amount of token to be swapped. It should be positive and if token is native, msg.value should be bigger than amount.
    /// @param tcRouter The router contract address of Thorchain. This cannot be hardcoded because Thorchain can upgrade its router and the address might change.
    /// @param tcVault The vault address of Thorchain. This cannot be hardcoded because Thorchain rotates vaults.
    /// @param thorchainMemo The transaction memo used by Thorchain which contains the thorchain swap data. More info: https://dev.thorchain.org/thorchain-dev/memos
    /// @param expiration The expiration block number. If the tx is included after this block, it will be reverted.
    function doSwapInToThorchain(
        address token,
        uint amount,
        address tcRouter,
        address tcVault,
        string calldata thorchainMemo,
        uint expiration
    ) internal {
        LibSwapper.BaseSwapperStorage storage baseStorage = LibSwapper.getBaseSwapperStorage();
        require(baseStorage.whitelistContracts[tcRouter], "given thorchain router not whitelisted");

        IThorchainRouter(tcRouter).depositWithExpiry{value : token == LibSwapper.ETH ? amount : 0}(
            payable(tcVault), // address payable vault,
            token, // address asset,
            amount, // uint amount,
            thorchainMemo, // string calldata memo,
            expiration  // uint expiration) external payable;
        );
        emit ThorchainTxInitiated(tcVault, token, amount, thorchainMemo, expiration);
    }

}