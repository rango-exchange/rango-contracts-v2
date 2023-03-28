// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.16;

import "../../interfaces/IWETH.sol";
import "../../interfaces/IRangoHyphen.sol";
import "../../interfaces/IRango.sol";
import "../../interfaces/IHyphenBridge.sol";
import "../../utils/ReentrancyGuard.sol";
import "../../libraries/LibSwapper.sol";
import "../../libraries/LibDiamond.sol";

/// @title The root contract that handles Rango's interaction with hyphen
/// @author Hellboy
contract RangoHyphenFacet is IRango, ReentrancyGuard, IRangoHyphen {

    /// Storage ///
    /// @dev keccak256("exchange.rango.facets.hyphen")
    bytes32 internal constant HYPHEN_NAMESPACE = hex"e55d91fd33507c47be7760850d08c4215f74dbd7bc3c006505d8961de648af93";

    struct HyphenStorage {
        /// @notice The address of hyphen contract
        address hyphenAddress;
    }

    /// @notice Emits when the hyphen address is updated
    /// @param _oldAddress The previous address
    /// @param _newAddress The new address
    event HyphenAddressUpdated(address _oldAddress, address _newAddress);

    /// @notice Initialize the contract.
    /// @param hyphenAddress The contract address of hyphen contract.
    function initHyphen(address hyphenAddress) external {
        LibDiamond.enforceIsContractOwner();
        updateHyphenAddressInternal(hyphenAddress);
    }

    /// @notice Executes a DEX (arbitrary) call + a hyphen bridge function
    /// @param request The general swap request containing from/to token and fee/affiliate rewards
    /// @param calls The list of DEX calls, if this list is empty, it means that there is no DEX call and we are only bridging
    /// @param bridgeRequest data related to hyphen bridge
    /// @dev If this function is a success, user will automatically receive the fund in the destination in their wallet (receiver)
    function hyphenSwapAndBridge(
        LibSwapper.SwapRequest memory request,
        LibSwapper.Call[] calldata calls,
        IRangoHyphen.HyphenBridgeRequest memory bridgeRequest
    ) external payable nonReentrant {
        uint out = LibSwapper.onChainSwapsPreBridge(request, calls, 0);
        HyphenStorage storage s = getHyphenStorage();
        if (request.toToken != LibSwapper.ETH) 
            LibSwapper.approveMax(request.toToken, s.hyphenAddress, out);
        doHyphenBridge(bridgeRequest, request.toToken, out);

        // event emission
        emit RangoBridgeInitiated(
            request.requestId,
            request.toToken,
            out,
            bridgeRequest.receiver,
            bridgeRequest.toChainId,
            false,
            false,
            uint8(BridgeType.Hyphen),
            request.dAppTag
        );
    }

    /// @notice Executes a hyphen bridge function
    /// @param request The request object containing required field by hyphen bridge
    function hyphenBridge(
        IRangoHyphen.HyphenBridgeRequest memory request,
        RangoBridgeRequest memory bridgeRequest
    ) external payable nonReentrant {
        HyphenStorage storage s = getHyphenStorage();
        uint256 amountWithFee = bridgeRequest.amount + LibSwapper.sumFees(bridgeRequest);
        // transfer tokens if necessary
        if (bridgeRequest.token == LibSwapper.ETH) {
            require(msg.value >= amountWithFee, "Insufficient ETH sent for bridging");
        } else {
            SafeERC20.safeTransferFrom(IERC20(bridgeRequest.token), msg.sender, address(this), amountWithFee);
            LibSwapper.approveMax(bridgeRequest.token, s.hyphenAddress, bridgeRequest.amount);
        }
        LibSwapper.collectFees(bridgeRequest);
        doHyphenBridge(request, bridgeRequest.token, bridgeRequest.amount);

        // event emission
        emit RangoBridgeInitiated(
            bridgeRequest.requestId,
            bridgeRequest.token,
            bridgeRequest.amount,
            request.receiver,
            request.toChainId,
            false,
            false,
            uint8(BridgeType.Hyphen),
            bridgeRequest.dAppTag
        );
    }

    /// @notice Executes a bridging via hyphen
    /// @param request The extra fields required by the hyphen bridge
    /// @param token The requested token to bridge
    /// @param amount The requested amount to bridge
    function doHyphenBridge(
        HyphenBridgeRequest memory request,
        address token,
        uint256 amount
    ) internal {
        HyphenStorage storage s = getHyphenStorage();
        address receiver = request.receiver;
        uint dstChainId = request.toChainId;

        require(s.hyphenAddress != LibSwapper.ETH, 'Hyphen address not set');
        require(block.chainid != dstChainId, 'Cannot bridge to the same network');

        if (token == LibSwapper.ETH) {
            IHyphenBridge(s.hyphenAddress).depositNative{ value: amount }(receiver, dstChainId, "Rango");
        } else{
            IHyphenBridge(s.hyphenAddress).depositErc20(dstChainId, token, receiver, amount, "Rango");
        }
    }

    function updateHyphenAddressInternal(address _address) private {
        require(_address != address(0), "Invalid Hyphen Address");
        HyphenStorage storage s = getHyphenStorage();
        address oldAddress = s.hyphenAddress;
        s.hyphenAddress = _address;
        emit HyphenAddressUpdated(oldAddress, _address);
    }

    /// @dev fetch local storage
    function getHyphenStorage() private pure returns (HyphenStorage storage s) {
        bytes32 namespace = HYPHEN_NAMESPACE;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            s.slot := namespace
        }
    }
}