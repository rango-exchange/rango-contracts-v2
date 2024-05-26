// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import "../libraries/LibSwapper.sol";
import "./IRango.sol";

interface IRangoCCTP {
    /// @notice The request object for CCTP bridge call
    struct CCTPRequest {
        uint32 destinationDomainId;
        bytes32 recipient;
        uint256 destinationChainId;
    }

    function cctpSwapAndBridge(
        LibSwapper.SwapRequest memory request,
        LibSwapper.Call[] calldata calls,
        IRangoCCTP.CCTPRequest memory bridgeRequest
    ) external payable;

    function cctpBridge(
        IRangoCCTP.CCTPRequest memory request,
        IRango.RangoBridgeRequest memory bridgeRequest
    ) external payable;

}
