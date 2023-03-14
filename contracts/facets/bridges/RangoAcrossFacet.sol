// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "../../interfaces/IAcrossSpokePool.sol";
import "../../interfaces/IRangoAcross.sol";
import "../../interfaces/IRango.sol";
import "../../utils/ReentrancyGuard.sol";
import "../../libraries/LibSwapper.sol";
import "../../libraries/LibDiamond.sol";

/// @title The root contract that handles Rango's interaction with Across bridge
/// @author Thinking Particle & AMA
/// @dev This is deployed as a facet for RangoDiamond
contract RangoAcrossFacet is IRango, ReentrancyGuard, IRangoAcross {

    /// Storage ///

    /// @dev keccak256("exchange.rango.facets.across")
    bytes32 internal constant ACROSS_NAMESPACE = hex"4e63b982873f293633572d65fbc8b8e979949d7d2e57c548af3c9d5fc8844dbb";

    struct AcrossStorage {
        /// @notice List of whitelisted Across spoke pools in the current chain
        mapping(address => bool) acrossSpokePools;
        bytes acrossRewardBytes;
    }

    /// Events ///

    /// @notice Notifies that some new spoke pool addresses are whitelisted
    /// @param _addresses The newly whitelisted addresses
    event AcrossSpokePoolsAdded(address[] _addresses);
    /// @notice Notifies that reward bytes are updated
    /// @param rewardBytes The newly set rewardBytes
    event AcrossRewardBytesUpdated(bytes rewardBytes);
    /// @notice Notifies that some spoke pool addresses are blacklisted
    /// @param _addresses The addresses that are removed
    event AcrossSpokePoolsRemoved(address[] _addresses);

    /// Initialization ///

    /// @notice Initialize the contract.
    /// @param _addresses The contract address of the spoke pool on the source chain.
    /// @param acrossRewardBytes The rewardBytes passed to across pool
    function initAcross(address[] calldata _addresses, bytes calldata acrossRewardBytes) external {
        LibDiamond.enforceIsContractOwner();
        addAcrossSpokePoolsInternal(_addresses);
        setAcrossRewardBytesInternal(acrossRewardBytes);
    }

    /// @notice Enables the contract to receive native ETH token from other contracts including WETH contract
    receive() external payable {}

    /// @notice Adds a list of new addresses to the whitelisted Across spokePools
    /// @param _addresses The list of new routers
    function addAcrossSpokePools(address[] calldata _addresses) public {
        LibDiamond.enforceIsContractOwner();

        addAcrossSpokePoolsInternal(_addresses);
    }
    /// @notice Adds a list of new addresses to the whitelisted Across spokePools
    /// @param acrossRewardBytes The rewardBytes passed to across contract
    function setAcrossRewardBytes(bytes calldata acrossRewardBytes) public {
        LibDiamond.enforceIsContractOwner();
        setAcrossRewardBytesInternal(acrossRewardBytes);
    }

    /// @notice Removes a list of routers from the whitelisted addresses
    /// @param _addresses The list of addresses that should be deprecated
    function removeAcrossSpokePools(address[] calldata _addresses) external {
        LibDiamond.enforceIsContractOwner();
        AcrossStorage storage s = getAcrossStorage();
        for (uint i = 0; i < _addresses.length; i++) {
            delete s.acrossSpokePools[_addresses[i]];
        }

        emit AcrossSpokePoolsRemoved(_addresses);
    }

    /// @notice Executes a DEX (arbitrary) call + a Across bridge call
    /// @dev request.toToken can be address(0) for native deposits and will be replaced in doAcrossBridge
    /// @param request The general swap request containing from/to token and fee/affiliate rewards
    /// @param calls The list of DEX calls, if this list is empty, it means that there is no DEX call and we are only bridging
    /// @param bridgeRequest required data for the bridging step, including the destination chain and recipient wallet address
    function acrossSwapAndBridge(
        LibSwapper.SwapRequest memory request,
        LibSwapper.Call[] calldata calls,
        AcrossBridgeRequest memory bridgeRequest
    ) external payable nonReentrant {
        uint out = LibSwapper.onChainSwapsPreBridge(request, calls, 0);
        if (request.toToken != LibSwapper.ETH)
            LibSwapper.approve(request.toToken, bridgeRequest.spokePoolAddress, out);
        doAcrossBridge(bridgeRequest, request.toToken, out);
        // event emission
        emit RangoBridgeInitiated(
            request.requestId,
            request.toToken,
            out,
            bridgeRequest.recipient,
            bridgeRequest.destinationChainId,
            false,
            false,
            uint8(BridgeType.Across),
            request.dAppTag);
    }

    /// @notice starts bridging through Across bridge
    /// @dev request.toToken can be address(0) for native deposits and will be replaced in doAcrossBridge
    function acrossBridge(
        AcrossBridgeRequest memory request,
        IRango.RangoBridgeRequest memory bridgeRequest
    ) external payable nonReentrant {
        uint amount = bridgeRequest.amount;
        address token = bridgeRequest.token;
        uint amountWithFee = amount + LibSwapper.sumFees(bridgeRequest);
        // transfer tokens if necessary
        if (token == LibSwapper.ETH) {
            require(
                msg.value >= amountWithFee, "Insufficient ETH sent for bridging and fees");
        } else {
            SafeERC20.safeTransferFrom(IERC20(token), msg.sender, address(this), amountWithFee);
            LibSwapper.approve(token, request.spokePoolAddress, amount);
        }
        LibSwapper.collectFees(bridgeRequest);
        doAcrossBridge(request, token, amount);

        // event emission
        emit RangoBridgeInitiated(
            bridgeRequest.requestId,
            token,
            amount,
            request.recipient,
            request.destinationChainId,
            false,
            false,
            uint8(BridgeType.Across),
            bridgeRequest.dAppTag
        );
    }

    /// @notice Executes an Across bridge call
    /// @dev bridgeRequest.originToken can be address(0) for native deposits
    /// @param request The other required fields for across bridge contract
    /// @param amount Amount of tokens to deposit. Will be amount of tokens to receive less fees.
    function doAcrossBridge(
        AcrossBridgeRequest memory request,
        address token,
        uint amount
    ) internal {
        AcrossStorage storage s = getAcrossStorage();
        require(s.acrossSpokePools[request.spokePoolAddress], "Requested spokePool address not whitelisted");
        address bridgeToken = token;
        if (token == LibSwapper.ETH) bridgeToken = LibSwapper.getBaseSwapperStorage().WETH;

        bytes memory acrossCallData = encodeWithSignature(
            request.recipient,
            bridgeToken,
            amount,
            request.destinationChainId,
            request.relayerFeePct,
            request.quoteTimestamp
        );

        bytes memory callData = concat(acrossCallData, s.acrossRewardBytes);

        (bool success, bytes memory ret) = request.spokePoolAddress.call{value : token == LibSwapper.ETH ? amount : 0}(callData);
        if (!success)
            revert(LibSwapper._getRevertMsg(ret));

    }

    function concat(bytes memory a, bytes memory b) internal pure returns (bytes memory) {
        return abi.encodePacked(a, b);
    }

    function encodeWithSignature(
        address recipient,
        address originToken,
        uint256 amount,
        uint256 destinationChainId,
        uint64 relayerFeePct,
        uint32 quoteTimestamp
    ) public pure returns (bytes memory) {
        return abi.encodeWithSignature("deposit(address,address,uint256,uint256,uint64,uint32)",
            recipient, originToken, amount, destinationChainId, relayerFeePct, quoteTimestamp
        );
    }

    function addAcrossSpokePoolsInternal(address[] calldata _addresses) private {
        AcrossStorage storage s = getAcrossStorage();

        address tmpAddr;
        for (uint i = 0; i < _addresses.length; i++) {
            tmpAddr = _addresses[i];
            require(tmpAddr != address(0), "Invalid SpokePool Address");
            s.acrossSpokePools[tmpAddr] = true;
        }

        emit AcrossSpokePoolsAdded(_addresses);
    }

    function setAcrossRewardBytesInternal(bytes calldata acrossRewardBytes) private {
        AcrossStorage storage s = getAcrossStorage();
        s.acrossRewardBytes = acrossRewardBytes;
        emit AcrossRewardBytesUpdated(acrossRewardBytes);
    }

    /// @dev fetch local storage
    function getAcrossStorage() private pure returns (AcrossStorage storage s) {
        bytes32 namespace = ACROSS_NAMESPACE;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            s.slot := namespace
        }
    }

}