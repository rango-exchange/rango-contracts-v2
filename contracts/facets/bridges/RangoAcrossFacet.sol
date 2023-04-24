// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.16;

import "../../interfaces/IAcrossSpokePool.sol";
import "../../interfaces/IRangoAcross.sol";
import "../../interfaces/IRango.sol";
import "../../utils/ReentrancyGuard.sol";
import "../../libraries/LibSwapper.sol";
import "../../libraries/LibDiamond.sol";
import "../../interfaces/Interchain.sol";
import "@openzeppelin/contracts/interfaces/IERC1271.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";


/// @title The root contract that handles Rango's interaction with Across bridge
/// @author Thinking Particle & AMA
/// @dev This is deployed as a facet for RangoDiamond
contract RangoAcrossFacet is IRango, ReentrancyGuard, IRangoAcross, IERC1271 {

    /// Storage ///

    /// @dev keccak256("exchange.rango.facets.across")
    bytes32 internal constant ACROSS_NAMESPACE = hex"4e63b982873f293633572d65fbc8b8e979949d7d2e57c548af3c9d5fc8844dbb";

    struct AcrossStorage {
        /// @notice whitelisted Across spoke pool in current chain
        address acrossSpokePool;
        mapping(bytes32 => bool) refundHashes;
        mapping(uint32 => address) depositIdToAddress;
        bytes acrossRewardBytes;
    }

    /// Events ///

    /// @notice Notifies that spoke pool address is updated
    /// @param _address The newly whitelisted addresse
    event AcrossSpokePoolUpdated(address _address);
    /// @notice Notifies that reward bytes are updated
    /// @param rewardBytes The newly set rewardBytes
    event AcrossRewardBytesUpdated(bytes rewardBytes);

    /// Initialization ///

    /// @notice Initialize the contract.
    /// @param _spokePoolAddress The contract address of the spoke pool on the source chain.
    /// @param acrossRewardBytes The rewardBytes passed to across pool
    function initAcross(address _spokePoolAddress, bytes calldata acrossRewardBytes) external {
        LibDiamond.enforceIsContractOwner();
        updateAcrossSpokePoolInternal(_spokePoolAddress);
        setAcrossRewardBytesInternal(acrossRewardBytes);
    }

    /// @notice Enables the contract to receive native ETH token from other contracts including WETH contract
    receive() external payable {}

    /// @notice updates the adress of spoke pool in current chain
    /// @param _address new address for spoke pool
    function updateAcrossSpokePool(address _address) public {
        LibDiamond.enforceIsContractOwner();

        updateAcrossSpokePoolInternal(_address);
    }
    /// @notice Adds a list of new addresses to the whitelisted Across spokePools
    /// @param acrossRewardBytes The rewardBytes passed to across contract
    function setAcrossRewardBytes(bytes calldata acrossRewardBytes) public {
        LibDiamond.enforceIsContractOwner();
        setAcrossRewardBytesInternal(acrossRewardBytes);
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

        doAcrossBridge(bridgeRequest, request.toToken, out);

        bool hasInterchainMessage = bridgeRequest.message.length > 0;
        bool hasDestSwap = false;
        if (hasInterchainMessage == true) {
            Interchain.RangoInterChainMessage memory imMessage = abi.decode((bridgeRequest.message), (Interchain.RangoInterChainMessage));
            hasDestSwap = imMessage.actionType != Interchain.ActionType.NO_ACTION;
        }

        // event emission
        emit RangoBridgeInitiated(
            request.requestId,
            request.toToken,
            out,
            bridgeRequest.recipient,
            bridgeRequest.destinationChainId,
            hasInterchainMessage,
            hasDestSwap,
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
        }
        LibSwapper.collectFees(bridgeRequest);
        doAcrossBridge(request, token, amount);

        bool hasInterchainMessage = request.message.length > 0;
        bool hasDestSwap = false;
        if (hasInterchainMessage == true) {
            Interchain.RangoInterChainMessage memory imMessage = abi.decode((request.message), (Interchain.RangoInterChainMessage));
            hasDestSwap = imMessage.actionType != Interchain.ActionType.NO_ACTION;
        }

        // event emission
        emit RangoBridgeInitiated(
            bridgeRequest.requestId,
            token,
            amount,
            request.recipient,
            request.destinationChainId,
            hasInterchainMessage,
            hasDestSwap,
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
        require(s.acrossSpokePool != address(0));
        if (token != LibSwapper.ETH)
            LibSwapper.approveMax(token, s.acrossSpokePool, amount);

        address bridgeToken = token;
        if (token == LibSwapper.ETH) bridgeToken = LibSwapper.getBaseSwapperStorage().WETH;

        bytes memory acrossCallData = encodeWithSignature(
            request.recipient,
            bridgeToken,
            amount,
            request.destinationChainId,
            request.relayerFeePct,
            request.quoteTimestamp,
            request.message,
            request.maxCount
        );

        bytes memory callData = concat(acrossCallData, s.acrossRewardBytes);

        // store depositId to use later for refunds if necessary
        uint32 depositId = IAcrossSpokePool(s.acrossSpokePool).numberOfDeposits();
        s.depositIdToAddress[depositId] = msg.sender;

        (bool success, bytes memory ret) = s.acrossSpokePool.call{value : token == LibSwapper.ETH ? amount : 0}(callData);
        if (!success)
            revert(LibSwapper._getRevertMsg(ret));

    }

    /// @notice Speed up or update an Across bridge call for unstuck
    /// @dev This can be used to unstuck transactions on destination by changing recipient or message
    function speedUpAcrossDeposit(
        int64 updatedRelayerFeePct,
        uint32 depositId,
        address updatedRecipient,
        bytes memory updatedMessage,
        bytes memory depositorSignature
    ) external nonReentrant {
        AcrossStorage storage s = getAcrossStorage();
        require(s.acrossSpokePool != address(0));

        address _owner = LibDiamond.contractOwner();
        if (msg.sender != _owner && s.depositIdToAddress[depositId] != msg.sender) {
            revert("Sender should be owner or the original depositor");
        }

        // register refund hash
        bytes32 _hash = getTypedDataV4Hash(
            depositId,
            block.chainid,
            updatedRelayerFeePct,
            updatedRecipient,
            updatedMessage
        );
        s.refundHashes[_hash] = true;

        IAcrossSpokePool(s.acrossSpokePool).speedUpDeposit(
            address(this),
            updatedRelayerFeePct,
            depositId,
            updatedRecipient,
            updatedMessage,
            depositorSignature
        );
        s.refundHashes[_hash] = false;
    }

    /// @notice Speed up or update an Across bridge call for unstuck
    /// @dev This can be used to unstuck transactions on destination by changing recipient or message
    function speedUpAcrossDepositWithHash(
        bytes32 hash,
        int64 updatedRelayerFeePct,
        uint32 depositId,
        address updatedRecipient,
        bytes memory updatedMessage,
        bytes memory depositorSignature
    ) external nonReentrant {
        AcrossStorage storage s = getAcrossStorage();

        address _owner = LibDiamond.contractOwner();
        if (msg.sender != _owner && s.depositIdToAddress[depositId] != msg.sender) {
            revert("Sender should be owner or the original depositor");
        }

        require(s.acrossSpokePool != address(0));

        // register refund hash
        s.refundHashes[hash] = true;

        IAcrossSpokePool(s.acrossSpokePool).speedUpDeposit(
            address(this),
            updatedRelayerFeePct,
            depositId,
            updatedRecipient,
            updatedMessage,
            depositorSignature
        );
        s.refundHashes[hash] = false;
    }


    // @dev Important Note: If any facets needs to support EIP1271 in future, we should have a function that supports EIP1271 for all facets. Otherwise, only one facet will have isValidSignature and others will be left out
    function isValidSignature(bytes32 hash, bytes memory signature) external view returns (bytes4){
        AcrossStorage storage s = getAcrossStorage();
        bytes4 MAGICVALUE = 0x1626ba7e;
        // handle eip1271 for across bridge
        if (s.acrossSpokePool == msg.sender) {
            if (s.refundHashes[hash] == true) {
                return MAGICVALUE;
            }
        }
        // sender is not across bridge. We can handle other cases here later if needed.
        return 0xffffffff;
    }

    /// @dev This function is based on Across SpokePool and _hashTypedDataV4, to get the hashed of data.
    function getTypedDataV4Hash(
        uint32 depositId,
        uint256 originChainId,
        int64 updatedRelayerFeePct,
        address updatedRecipient,
        bytes memory updatedMessage
    ) public pure returns (bytes32){

        bytes32 hashedName = keccak256(bytes("ACROSS-V2"));
        bytes32 hashedVersion = keccak256(bytes("1.0.0"));
        bytes32 _HASHED_NAME = hashedName;
        bytes32 _HASHED_VERSION = hashedVersion;
        bytes32 _TYPE_HASH = keccak256("EIP712Domain(string name,string version,uint256 chainId)");

        bytes32 domainSep = keccak256(abi.encode(_TYPE_HASH, _HASHED_NAME, _HASHED_VERSION, originChainId));
        bytes32 UPDATE_DEPOSIT_DETAILS_HASH = keccak256(
            "UpdateDepositDetails(uint32 depositId,uint256 originChainId,int64 updatedRelayerFeePct,address updatedRecipient,bytes updatedMessage)"
        );

        bytes32 structHash = keccak256(
            abi.encode(
                UPDATE_DEPOSIT_DETAILS_HASH,
                depositId,
                originChainId,
                updatedRelayerFeePct,
                updatedRecipient,
                keccak256(updatedMessage)
            )
        );
        return ECDSAUpgradeable.toTypedDataHash(domainSep, structHash);
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
        uint32 quoteTimestamp,
        bytes memory message,
        uint256 maxCount
    ) public pure returns (bytes memory) {
        return abi.encodeWithSignature("deposit(address,address,uint256,uint256,uint64,uint32,bytes,uint256)",
            recipient, originToken, amount, destinationChainId, relayerFeePct, quoteTimestamp, message, maxCount
        );
    }

    function updateAcrossSpokePoolInternal(address _address) private {
        AcrossStorage storage s = getAcrossStorage();
        s.acrossSpokePool = _address;
        require(_address != address(0), "Invalid SpokePool Address");
        emit AcrossSpokePoolUpdated(_address);
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