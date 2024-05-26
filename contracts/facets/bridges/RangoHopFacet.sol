// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import "../../interfaces/IHop.sol";
import "../../interfaces/IRangoHop.sol";
import "../../interfaces/IRango.sol";
import "../../utils/ReentrancyGuard.sol";
import "../../libraries/LibSwapper.sol";
import "../../libraries/LibDiamond.sol";

/// @title The root contract that handles Rango's interaction with Hop bridge
/// @author Uchiha Sasuke
contract RangoHopFacet is IRango, ReentrancyGuard, IRangoHop {

    /// Storage ///
    /// @dev keccak256("exchange.rango.facets.hop")
    bytes32 internal constant HOP_NAMESPACE = hex"e55d91fd33507c47be7760850d08c4215f74dbd7bc3c006505d8961de648af93";

    struct HopStorage {
        /// @notice List of whitelisted Hop bridge addresses in the current chain
        mapping(address => bool) hopBridges;
    }

    /// @notice Notifies that some new hop bridge addresses are whitelisted
    /// @param _addresses The newly whitelisted addresses
    event HopBridgesAdded(address[] _addresses);

    /// @notice Notifies that some hop bridge addresses are blacklisted
    /// @param _addresses The addresses that are removed
    event HopBridgesRemoved(address[] _addresses);

    /// @notice An event showing that a Hop bridge call happened
    event HopBridgeSent(
        address bridgeAddress,
        HopActionType actionType,
        uint256 chainId,
        address recipient,
        uint256 amount,
        uint256 bonderFee,
        uint256 amountOutMin,
        uint256 deadline,
        uint256 destinationAmountOutMin,
        uint256 destinationDeadline,
        address relayer,
        uint256 relayerFee
    );

    /// Constructor ///

    /// @notice Initialize the contract.
    /// @param _addresses The contract address of the spoke pool on the source chain.
    function initHop(address[] calldata _addresses) external {
        LibDiamond.enforceIsContractOwner();
        addHopBridgesInternal(_addresses);
    }

    /// @notice Enables the contract to receive native ETH token from other contracts including WETH contract
    receive() external payable { }

    /// @notice Removes a list of routers from the whitelisted addresses
    /// @param _addresses The list of addresses that should be deprecated
    function removeHopBridges(address[] calldata _addresses) external {
        LibDiamond.enforceIsContractOwner();
        HopStorage storage s = getHopStorage();

        for (uint i = 0; i < _addresses.length; i++) {
            delete s.hopBridges[_addresses[i]];
        }

        emit HopBridgesRemoved(_addresses);
    }

    /// @notice Executes a DEX (arbitrary) call + a Hop bridge call
    /// @param request The general swap request containing from/to token and fee/affiliate rewards
    /// @param calls The list of DEX calls, if this list is empty, it means that there is no DEX call and we are only bridging
    /// @param bridgeRequest required data for the bridging step, including the destination chain and recipient wallet address
    function hopSwapAndBridge(
        LibSwapper.SwapRequest memory request,
        LibSwapper.Call[] calldata calls,
        IRangoHop.HopRequest memory bridgeRequest
    ) external payable nonReentrant {
        uint out = LibSwapper.onChainSwapsPreBridge(request, calls, 0);
        if (request.toToken != LibSwapper.ETH) 
            LibSwapper.approveMax(request.toToken, bridgeRequest.bridgeAddress, out);
        doHopBridge(bridgeRequest, request.toToken, out);

        // event emission
        emit RangoBridgeInitiated(
            request.requestId,
            request.toToken,
            out,
            bridgeRequest.recipient,
            bridgeRequest.chainId,
            false,
            false,
            uint8(BridgeType.Hop),
            request.dAppTag
        );
    }

    /// @notice Executes a Hop bridge call
    /// @param request The request object containing required field by hop bridge
    function hopBridge(
        IRangoHop.HopRequest memory request,
        RangoBridgeRequest memory bridgeRequest
    ) external payable nonReentrant {
        HopStorage storage s = getHopStorage();
        uint256 amountWithFee = bridgeRequest.amount + LibSwapper.sumFees(bridgeRequest);
        // transfer tokens if necessary
        if (bridgeRequest.token == LibSwapper.ETH) {
            require(msg.value >= amountWithFee, "Insufficient ETH sent for bridging");
        } else {
            SafeERC20.safeTransferFrom(IERC20(bridgeRequest.token), msg.sender, address(this), amountWithFee);
            LibSwapper.approveMax(bridgeRequest.token, request.bridgeAddress, bridgeRequest.amount);
        }

        LibSwapper.collectFees(bridgeRequest);
        doHopBridge(request, bridgeRequest.token, bridgeRequest.amount);

        // event emission
        emit RangoBridgeInitiated(
            bridgeRequest.requestId,
            bridgeRequest.token,
            bridgeRequest.amount,
            request.recipient,
            request.chainId,
            false,
            false,
            uint8(BridgeType.Hop),
            bridgeRequest.dAppTag
        );
    }


    /// @notice Executes a Hop bridge call
    /// @param request The request object containing required field by hop bridge
    /// @param amount The amount to be bridged
    function doHopBridge(
        HopRequest memory request,
        address fromToken,
        uint amount
    ) internal {
        HopStorage storage s = getHopStorage();
        require(s.hopBridges[request.bridgeAddress], "Requested hop address not whitelisted");
        uint value = fromToken == LibSwapper.ETH ? amount : 0;
        
        IHop hop = IHop(request.bridgeAddress);
        if (request.actionType == HopActionType.SWAP_AND_SEND) {
            require(block.chainid != 1, "swapAndSend called from L1");
            hop.swapAndSend{value : value}(
                request.chainId,
                request.recipient,
                amount,
                request.bonderFee,
                request.amountOutMin,
                request.deadline,
                request.destinationAmountOutMin,
                request.destinationDeadline
            );
        } else if (request.actionType == HopActionType.SEND_TO_L2) {
            require(block.chainid == 1, "sendToL2 not called from L1");
            hop.sendToL2{value : value}(
                request.chainId,
                request.recipient,
                amount,
                request.amountOutMin,
                request.deadline,
                request.relayer,
                request.relayerFee
            );
        }

        emitHopEvent(request, amount);
    }

    function emitHopEvent(HopRequest memory request, uint amount) private {
        emit HopBridgeSent(
            request.bridgeAddress,
            request.actionType,
            request.chainId,
            request.recipient,
            amount,
            request.bonderFee,
            request.amountOutMin,
            request.deadline,
            request.destinationAmountOutMin,
            request.destinationDeadline,
            request.relayer,
            request.relayerFee
        );
    }

    function addHopBridgesInternal(address[] calldata _addresses) private {
        HopStorage storage s = getHopStorage();

        address tmpAddr;
        for (uint i = 0; i < _addresses.length; i++) {
            tmpAddr = _addresses[i];
            require(tmpAddr != address(0), "Invalid Hop Address");
            s.hopBridges[tmpAddr] = true;
        }

        emit HopBridgesAdded(_addresses);
    }

    /// @dev fetch local storage
    function getHopStorage() private pure returns (HopStorage storage s) {
        bytes32 namespace = HOP_NAMESPACE;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            s.slot := namespace
        }
    }
}