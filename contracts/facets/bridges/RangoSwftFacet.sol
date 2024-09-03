// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import "../../interfaces/ISwft.sol";
import "../../interfaces/IRangoSwft.sol";
import "../../interfaces/IRango.sol";
import "../../utils/ReentrancyGuard.sol";
import "../../libraries/LibSwapper.sol";
import "../../libraries/LibDiamond.sol";
import "../../interfaces/Interchain.sol";
import "../../libraries/LibPausable.sol";

/// @title The root contract that handles Rango's interaction with SWFT bridge
/// @author George
/// @dev This is deployed as a facet for RangoDiamond
contract RangoSwftFacet is IRango, ReentrancyGuard, IRangoSwft {
    /// Storage ///
    bytes32 internal constant SWFT_NAMESPACE = keccak256("exchange.rango.facets.swft");

    struct SwftStorage {
        address swftContractAddress;
    }

    /// Events ///

    /// @notice Notifies that swft contract address is updated
    /// @param _oldAddress The previous swft contract address
    /// @param _newAddress The newly set swft contract address
    event SwftContractAddressUpdated(address _oldAddress, address _newAddress);

    /// Initialization ///

    /// @notice Initialize the contract.
    /// @param _swftContractAddress The contract address of the SWFT
    function initSwft(address _swftContractAddress) external {
        LibDiamond.enforceIsContractOwner();
        updateSwftContractAddressInternal(_swftContractAddress);
    }

    /// @notice update the Swft contract address
    /// @param _swftContractAddress The contract address of the SWFT
    function updateSwftContractAddress(address _swftContractAddress) public {
        LibDiamond.enforceIsContractOwner();
        updateSwftContractAddressInternal(_swftContractAddress);
    }

    /// @notice Executes a DEX (arbitrary) call + a Swft bridge call
    /// @param request The general swap request containing from/to token and fee/affiliate rewards
    /// @param calls The list of DEX calls, if this list is empty, it means that there is no DEX call and we are only bridging
    /// @param bridgeRequest required data for the bridging step, including the destination chain and recipient wallet address
    function swftSwapAndBridge(
        LibSwapper.SwapRequest memory request,
        LibSwapper.Call[] calldata calls,
        SwftBridgeRequest memory bridgeRequest
    ) external payable nonReentrant {
        LibPausable.enforceNotPaused();
        uint out = LibSwapper.onChainSwapsPreBridge(request, calls, 0);

        doSwftBridge(bridgeRequest, request.toToken, out);

        // event emission
        emit RangoBridgeInitiated(
            request.requestId,
            request.toToken,
            out,
            LibSwapper.ETH,
            0,
            false,
            false,
            uint8(BridgeType.Swft),
            request.dAppTag,
            request.dAppName
        );
    }

    /// @notice starts bridging through Swft bridge
    /// @param request The extra fields required by the Swft
    function swftBridge(
        SwftBridgeRequest memory request,
        IRango.RangoBridgeRequest memory bridgeRequest
    ) external payable nonReentrant {
        LibPausable.enforceNotPaused();
        uint amount = bridgeRequest.amount;
        address token = bridgeRequest.token;
        uint amountWithFee = amount + LibSwapper.sumFees(bridgeRequest);
        // transfer tokens if necessary
        if (token == LibSwapper.ETH) {
            require(
                msg.value >= amountWithFee, "Insufficient ETH sent for bridging and fees");
        } else {
            SafeERC20.safeTransferFrom(IERC20(token), msg.sender, address(this), amountWithFee);
        }
        LibSwapper.collectFees(bridgeRequest);
        doSwftBridge(request, token, amount);

        // event emission
        emit RangoBridgeInitiated(
            bridgeRequest.requestId,
            token,
            amount,
            LibSwapper.ETH,
            0,
            false,
            false,
            uint8(BridgeType.Swft),
            bridgeRequest.dAppTag,
            bridgeRequest.dAppName
        );
    }

    /// @notice Executes a Swft bridge call
    /// @param request The other required fields for swft bridge contract
    /// @param token can be address(0) for native deposits
    /// @param amount Amount of tokens to deposit. Will be amount of tokens to receive less fees.
    function doSwftBridge(
        SwftBridgeRequest memory request,
        address token,
        uint amount
    ) internal {
        SwftStorage storage s = getSwftStorage();
        require(s.swftContractAddress != address(0));
        if (token != LibSwapper.ETH) {
            LibSwapper.approveMax(token, s.swftContractAddress, amount);
            ISwft(s.swftContractAddress).swap(token, request.toToken, request.destination, amount, request.minReturnAmount);
        } else {
            ISwft(s.swftContractAddress).swapEth{value: amount}(request.toToken, request.destination, request.minReturnAmount);
        }
    }

    function updateSwftContractAddressInternal(address _swftContractAddress) private {
        SwftStorage storage s = getSwftStorage();
        address previousAddr = s.swftContractAddress;
        s.swftContractAddress = _swftContractAddress;
        emit SwftContractAddressUpdated(previousAddr, _swftContractAddress);
    }

    /// @dev fetch local storage
    function getSwftStorage() private pure returns (SwftStorage storage s) {
        bytes32 namespace = SWFT_NAMESPACE;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            s.slot := namespace
        }
    }

}