// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import "../libraries/LibSwapper.sol";
import "./IRango.sol";

/// @title Interface to interact with RangoThorchain contract.
/// @author Thinking Particle
interface IRangoThorchain {

    /// @notice The request object for Thorchain
    /// @param tcRouter The router contract address of Thorchain. This cannot be hardcoded because Thorchain can upgrade its router and the address might change.
    /// @param tcVault The vault address of Thorchain. This cannot be hardcoded because Thorchain rotates vaults.
    /// @param thorchainMemo The transaction memo used by Thorchain which contains the thorchain swap data. More info: https://dev.thorchain.org/
    /// @param expiration The expiration block number. If the tx is included after this block, it will be reverted.
    /// @param preventNonEoaSender If set to true, the transaction will revert if the msg.sender has contract code. This is to prevent funds getting stuck/lost in thorchain.
    struct ThorchainBridgeRequest {
        address tcRouter;
        address tcVault;
        string thorchainMemo;
        uint expiration;
        bool preventNonEoaSender;
    }

    /// @notice Swap tokens if necessary, then pass it to RangoThorchain
    /// @dev Swap tokens if necessary, then pass it to RangoThorchain. If no swap is required (calls.length==0) the provided token is passed to RangoThorchain without change.
    /// @param request The swap information used to check input and output token addresses and balances, as well as the fees if any. Together with calls param, determines the swap logic before passing to Thorchain.
    /// @param calls The contract call data that is used to swap (can be empty if no swap is needed). Together with request param, determines the swap logic before passing to Thorchain.
    /// @param bridgeRequest The required data to bridge with thorchain
    function thorchainSwapAndBridge(
        LibSwapper.SwapRequest memory request,
        LibSwapper.Call[] calldata calls,
        ThorchainBridgeRequest memory bridgeRequest
    ) external payable;

    /// @notice Do a swap through thorchain
    /// @param bridgeRequest The necessary data for bridging
    /// @param request The required data to bridge with thorchain
    function thorchainBridge(
        IRango.RangoBridgeRequest memory bridgeRequest,
        ThorchainBridgeRequest memory request
    ) external payable;

}