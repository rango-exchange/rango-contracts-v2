// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import "../../interfaces/IRango.sol";
import "../../interfaces/IRangoOptimism.sol";
import "../../interfaces/IOptimismL1XBridge.sol";
import "../../utils/ReentrancyGuard.sol";
import "../../libraries/LibSwapper.sol";
import "../../libraries/LibDiamond.sol";
import "../../libraries/LibPausable.sol";

/// @title The root contract that handles Rango's interaction with Optimism bridge
/// @author AMA
contract RangoOptimismBridgeFacet is IRango, ReentrancyGuard, IRangoOptimism {
    /// Storage ///
    bytes32 internal constant OPTIMISM_NAMESPACE = keccak256("exchange.rango.facets.optimism");

    struct OptimismBridgeStorage {
        mapping (address => bool) whitelistBridgeContracts;
    }

    struct OptimismBridgeInitData {
        address bridgeAddress;
    }

    /// @notice Notifies that some new optimism bridge addresses are whitelisted
    /// @param data The newly added bridge & token address
    event OptimismBridgesAdded(OptimismBridgeInitData[] data);

    /// @notice Notifies that some optimism bridge addresses are blacklisted
    /// @param data The  bridge & token addresses that are removed
    event OptimismBridgesRemoved(OptimismBridgeInitData[] data);

    /// @notice Notifies that optimism bridge started
    /// @param bridge The bridge address
    /// @param recipient The receiver of funds
    /// @param token The input token of the bridge
    /// @param amount The amount that should be bridged
    event OptimismBridgeCalled(address bridge, address recipient, address token, uint256 amount, bool isSynth);

    /// @notice Initialize the contract.
    /// @param data The contract address of the L1Bridge/ERC20Bridge and associated token on the source chain.
    function initOptimism(OptimismBridgeInitData[] calldata data) external {
        LibDiamond.enforceIsContractOwner();
        addOptimismBridgesInternal(data);
    }

    /// @notice Removes a list of routers from the whitelisted addresses
    /// @param data The contract address of the L1Bridge/ERC20Bridge and associated token that should be deprecated.
    function removeOptimismBridges(OptimismBridgeInitData[] calldata data) external {
        LibDiamond.enforceIsContractOwner();

        OptimismBridgeStorage storage s = getOptimismBridgeStorage();
        for (uint i = 0; i < data.length; i++) {
            delete s.whitelistBridgeContracts[data[i].bridgeAddress];
        }

        emit OptimismBridgesRemoved(data);
    }

    /// @notice Executes a DEX (arbitrary) call + a Optimism bridge call
    /// @param request The general swap request containing from/to token and fee/affiliate rewards
    /// @param calls The list of DEX calls, if this list is empty, it means that there is no DEX call and we are only bridging
    /// @param bridgeRequest required data for the bridging step, including the destination chain and recipient wallet address
    function optimismSwapAndBridge(
        LibSwapper.SwapRequest memory request,
        LibSwapper.Call[] calldata calls,
        IRangoOptimism.OptimismBridgeRequest memory bridgeRequest
    ) external payable nonReentrant {
        LibPausable.enforceNotPaused();
        uint out = LibSwapper.onChainSwapsPreBridge(request, calls, 0);

        doOptimismBridge(bridgeRequest, request.toToken, out);

        // event emission
        emit RangoBridgeInitiated(
            request.requestId,
            request.toToken,
            out,
            bridgeRequest.receiver,
            10,
            false,
            false,
            uint8(BridgeType.OptimismBridge),
            request.dAppTag,
            request.dAppName
        );
    }

    /// @notice Executes an optimism bridge call
    /// @param bridgeRequest The request object containing required field by optimism bridge
    function optimismBridge(
        IRangoOptimism.OptimismBridgeRequest memory request,
        RangoBridgeRequest memory bridgeRequest
    ) external payable nonReentrant {
        LibPausable.enforceNotPaused();
        uint256 amountWithFee = bridgeRequest.amount + LibSwapper.sumFees(bridgeRequest);
        // transfer tokens & check inputs if necessary
        if (bridgeRequest.token == LibSwapper.ETH) {
            require(msg.value >= amountWithFee, "Insufficient ETH sent for bridging");
        } else {
            SafeERC20.safeTransferFrom(IERC20(bridgeRequest.token), msg.sender, address(this), amountWithFee);
        }

        LibSwapper.collectFees(bridgeRequest);
        doOptimismBridge(request, bridgeRequest.token, bridgeRequest.amount);

        // event emission
        emit RangoBridgeInitiated(
            bridgeRequest.requestId,
            bridgeRequest.token,
            bridgeRequest.amount,
            request.receiver,
            10,
            false,
            false,
            uint8(BridgeType.OptimismBridge),
            bridgeRequest.dAppTag,
            bridgeRequest.dAppName
        );
    }

    /// @notice Executes a Optimism bridge call
    /// @param request The request object containing required field by Optimism bridge
    /// @param amount The amount to be bridged
    function doOptimismBridge(
        IRangoOptimism.OptimismBridgeRequest memory request,
        address fromToken,
        uint amount
    ) internal {
        OptimismBridgeStorage storage s = getOptimismBridgeStorage();
        require(s.whitelistBridgeContracts[request.bridgeAddress], 'UnAuthorized! bridge is not allowed!');
        address bridgeAddress = request.bridgeAddress;
        IOptimismL1XBridge bridge = IOptimismL1XBridge(bridgeAddress);
            
        if (fromToken == LibSwapper.ETH) {
            bridge.depositETHTo{ value: amount }(request.receiver, request.l2Gas, "");
        } else {
            LibSwapper.approveMax(fromToken, bridgeAddress, amount);

            if (request.isSynth) {
                bridge.depositTo(request.receiver, amount);
            } else {
                bridge.depositERC20To(
                    fromToken,
                    request.l2TokenAddress,
                    request.receiver,
                    amount,
                    request.l2Gas,
                    ""
                );
            }
        }

        emit OptimismBridgeCalled(bridgeAddress, request.receiver, fromToken, amount, request.isSynth);
    }

    function addOptimismBridgesInternal(OptimismBridgeInitData[] calldata data) private {
        OptimismBridgeStorage storage s = getOptimismBridgeStorage();

        address tmpBridgeAddr;
        for (uint i = 0; i < data.length; i++) {
            tmpBridgeAddr = data[i].bridgeAddress;
            require(tmpBridgeAddr != address(0), "Invalid Bridge Address");
            s.whitelistBridgeContracts[data[i].bridgeAddress] = true;
        }

        emit OptimismBridgesAdded(data);
    }

    /// @dev fetch local storage
    function getOptimismBridgeStorage() private pure returns (OptimismBridgeStorage storage s) {
        bytes32 namespace = OPTIMISM_NAMESPACE;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            s.slot := namespace
        }
    }
}