// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import "../../interfaces/IUniswapV2.sol";
import "../../interfaces/IWETH.sol";
import "../../interfaces/IRangoStargateV2.sol";
import "../../interfaces/IStargateV2.sol";
import "../../interfaces/Interchain.sol";
import "../../libraries/LibInterchain.sol";
import "../../interfaces/IRango.sol";
import "../../utils/ReentrancyGuard.sol";
import "../../utils/LibTransform.sol";
import "../../libraries/LibDiamond.sol";
import "../../libraries/LibPausable.sol";

/// @title The root contract that handles Rango's interaction with StargateV2.
/// @author George & AMA
contract RangoStargateV2Facet is IRango, ReentrancyGuard, IRangoStargateV2 {
    /// Storage ///
    /// @dev keccak256("exchange.rango.facets.stargatev2")
    bytes32 internal constant STARGATEV2_NAMESPACE = keccak256("exchange.rango.facets.stargatev2");

    struct StargateV2Storage {
        /// @notice The address of treasurer contract
        address stargateTreasurer;
    }

    /// @notice Initialize the contract.
    /// @param treasurer The new address of stargatev2 treasurer
    function initStargateV2(address treasurer) external {
        LibDiamond.enforceIsContractOwner();
        updateStargateV2TreasurerInternal(treasurer);
    }


    /// @notice Emits when the stargatev2 treasurer contract address is updated
    /// @param _oldTreasurer The previous treasurer address
    /// @param _newTreasurer The new treasurer address
    event StargateV2TreasurerAddressUpdated(address _oldTreasurer, address _newTreasurer);

    /// @notice Updates the address of stargatev2 contract
    /// @param _treasurer The new address of stargateV2 treasurer contract
    function updateStargateV2TreasurerAddress(address _treasurer) public {
        LibDiamond.enforceIsContractOwner();
        updateStargateV2TreasurerInternal(_treasurer);
    }
    
    function stargateV2SwapAndBridge(
        LibSwapper.SwapRequest memory request,
        LibSwapper.Call[] calldata calls,
        StargateV2Request memory stargateV2Request
    ) external payable nonReentrant {
        LibPausable.enforceNotPaused();
        uint bridgeAmount;
        // if toToken is native coin and the user has not paid fee in msg.value,
        // then the user can pay bridge fee using output of swap.
        if (request.toToken == LibSwapper.ETH && msg.value == 0) {
            bridgeAmount = LibSwapper.onChainSwapsPreBridge(request, calls, 0) - stargateV2Request.nativeFee;
        }
        else {
            bridgeAmount = LibSwapper.onChainSwapsPreBridge(request, calls, stargateV2Request.nativeFee);
        }
        doStargateV2(stargateV2Request, request.toToken, bridgeAmount);

        // event emission
        emit RangoBridgeInitiated(
            request.requestId,
            request.toToken,
            bridgeAmount,
            LibTransform.bytes32LeftPaddedToAddress(stargateV2Request.recipientAddress),
            stargateV2Request.dstChainId,
            stargateV2Request.composeMsg.length > 0,
            false,
            uint8(BridgeType.Stargate),
            request.dAppTag,
            request.dAppName
        );
    }

    function stargateV2Bridge(
        StargateV2Request memory stargateRequest,
        RangoBridgeRequest memory bridgeRequest
    ) external payable nonReentrant {
        LibPausable.enforceNotPaused();
        uint256 amountWithFee = bridgeRequest.amount + LibSwapper.sumFees(bridgeRequest);
        // transfer tokens if necessary
        if (bridgeRequest.token != LibSwapper.ETH) {
            SafeERC20.safeTransferFrom(IERC20(bridgeRequest.token), msg.sender, address(this), amountWithFee);
            require(msg.value >= stargateRequest.nativeFee, "Insufficient ETH sent for bridging");
        } else {
            require(msg.value >= amountWithFee + stargateRequest.nativeFee, "Insufficient ETH sent for bridging");
        }
        LibSwapper.collectFees(bridgeRequest);
        doStargateV2(stargateRequest, bridgeRequest.token, bridgeRequest.amount);

        // event emission
        emit RangoBridgeInitiated(
            bridgeRequest.requestId,
            bridgeRequest.token,
            bridgeRequest.amount,
            LibTransform.bytes32LeftPaddedToAddress(stargateRequest.recipientAddress),
            stargateRequest.dstChainId,
            stargateRequest.composeMsg.length > 0,
            false,
            uint8(BridgeType.Stargate),
            bridgeRequest.dAppTag,
            bridgeRequest.dAppName
        );
    }

    /// @notice Executes a Stargate call
    /// @param request Required bridge params + interchain message that contains all the required info on the destination
    /// @param fromToken The address of source token to bridge
    /// @param inputAmount The amount to be bridged (excluding the fee)
    function doStargateV2(
        StargateV2Request memory request,
        address fromToken,
        uint256 inputAmount
    ) internal {
        StargateV2Storage storage s = getStargateV2Storage();
        require(s.stargateTreasurer != address(0), "invalid treasurer");
        require(IStargateV2Treasurer(s.stargateTreasurer).stargates(request.poolContract) == true, "invalid stargate");
        if (fromToken != LibSwapper.ETH) {
            LibSwapper.approveMax(fromToken, request.poolContract, inputAmount);
        }

        IStargateV2.SendParam memory sendParam = IStargateV2.SendParam({
            dstEid: request.dstEid,
            to: request.recipientAddress,
            amountLD: inputAmount,
            minAmountLD: request.minAmountLD,
            extraOptions: request.extraOptions,
            composeMsg: request.composeMsg,
            oftCmd: request.oftCmd
        });

        uint value = (fromToken == LibSwapper.ETH ? inputAmount: 0 ) + request.nativeFee;
        IStargateV2(request.poolContract).send{value: value}(
            sendParam,
            IStargateV2.MessagingFee(request.nativeFee, 0),
            request.refundAddress == address(0) ? msg.sender : request.refundAddress
        ); 
        
    }

    function updateStargateV2TreasurerInternal(address _treasurer) private {
        require(_treasurer != address(0), "Invalid treasurer Address");
        StargateV2Storage storage s = getStargateV2Storage();
        address oldAddressTreasurer = s.stargateTreasurer;
        s.stargateTreasurer = _treasurer;

        emit StargateV2TreasurerAddressUpdated(oldAddressTreasurer, _treasurer);
    }

    /// @dev fetch local storage
    function getStargateV2Storage() private pure returns (StargateV2Storage storage s) {
        bytes32 namespace = STARGATEV2_NAMESPACE;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            s.slot := namespace
        }
    }
}