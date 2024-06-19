// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import "../../interfaces/IWETH.sol";
import "../../interfaces/IRangoYBridge.sol";
import "../../interfaces/IRango.sol";
import "../../interfaces/IYBridge.sol";
import "../../interfaces/IUniswapV2.sol";
import "../../interfaces/Interchain.sol";
import "../../libraries/LibInterchain.sol";
import "../../utils/LibTransform.sol";
import "../../utils/ReentrancyGuard.sol";
import "../../libraries/LibDiamond.sol";

/// @title The root contract that handles Rango's interaction with yBridge from xy finance
/// @author jeoffery
/// @dev This facet should be added to diamond.
contract RangoYBridgeFacet is IRango, ReentrancyGuard, IRangoYBridge {
    /// Storage ///
    /// @dev keccak256("exchange.rango.facets.yBridge")
    bytes32 internal constant YBRIDGE_NAMESPACE = hex"d3217d0de7a24581e333df3a18b696e34eb95ce343a4ce3fa174de6cf5c391ae";

    struct YBridgeStorage {
        /// @notice The address of yBridge contract
        address yBridgeAddress;
    }

    /// @notice Emitted when the yBridge address is updated
    /// @param _oldAddress The previous address
    /// @param _newAddress The new address
    event YBridgeAddressUpdated(address _oldAddress, address _newAddress);

    /// @notice Initialize the contract.
    /// @param _yBridgeAddress The address of ybridge contract
    function initYBridge(address _yBridgeAddress) external {
        LibDiamond.enforceIsContractOwner();
        updateYBridgeAddressInternal(_yBridgeAddress);
    }

    /// @notice Updates the address of yBridge contract
    /// @param _yBridgeAddress The new address of yBridge contract
    function updateYBridgeAddress(address _yBridgeAddress) public {
        LibDiamond.enforceIsContractOwner();
        updateYBridgeAddressInternal(_yBridgeAddress);
    }

    /// @notice Executes a DEX (arbitrary) call + a yBridge bridge call
    /// @param request The general swap request containing from/to token and fee/affiliate rewards
    /// @param calls The list of DEX calls, if this list is empty, it means that there is no DEX call and we are only bridging
    /// @param bridgeRequest required data for the bridging step, including the destination chain and recipient wallet address
    function yBridgeSwapAndBridge(
        LibSwapper.SwapRequest memory request,
        LibSwapper.Call[] calldata calls,
        YBridgeRequest memory bridgeRequest
    ) external payable nonReentrant {
        uint bridgeAmount = LibSwapper.onChainSwapsPreBridge(request, calls, 0);

        doYBridge(bridgeRequest, request.toToken, bridgeAmount);

        // event emission
        emit RangoBridgeInitiated(
            request.requestId,
            request.toToken,
            bridgeAmount,
            bridgeRequest.receiver,
            bridgeRequest.toChainId,
            false,
            false,
            uint8(BridgeType.YBridge),
            request.dAppTag,
            request.dAppName
        );
    }

    /// @notice Executes a bridging via yBridge
    /// @param request The extra fields required by the yBridge bridge
    function yBridgeBridge(
        YBridgeRequest memory request,
        RangoBridgeRequest memory bridgeRequest
    ) external payable nonReentrant {
        uint amount = bridgeRequest.amount;
        address token = bridgeRequest.token;
        uint amountWithFee = amount + LibSwapper.sumFees(bridgeRequest);
        // transfer tokens if necessary
        if (token != LibSwapper.ETH) {
            SafeERC20.safeTransferFrom(IERC20(token), msg.sender, address(this), amountWithFee);
        } else {
            require(msg.value >= amountWithFee);
        }
        LibSwapper.collectFees(bridgeRequest);
        doYBridge(request, token, amount);

        // event emission
        emit RangoBridgeInitiated(
            bridgeRequest.requestId,
            token,
            amount,
            request.receiver,
            request.toChainId,
            false,
            false,
            uint8(BridgeType.YBridge),
            bridgeRequest.dAppTag,
            bridgeRequest.dAppName
        );
    }

    /// @notice Executes a bridging via yBridge
    /// @param request The extra fields required by the yBridge bridge
    /// @param token The requested token to bridge
    /// @param amount The requested amount to bridge
    function doYBridge(
        YBridgeRequest memory request,
        address token,
        uint256 amount
    ) internal {
        YBridgeStorage storage s = getYBridgeStorage();

        require(s.yBridgeAddress != LibSwapper.ETH, 'yBridge address not set');
        require(block.chainid != request.toChainId, 'Invalid destination Chain! Cannot bridge to the same network.');

        address bridgeToken = token;
        uint256 value = 0;
        if (token == LibSwapper.ETH) {
            bridgeToken = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
            value = amount;
        } else {
            LibSwapper.approveMax(token, s.yBridgeAddress, amount);
        }

        // since we need no swap via xy, first two arguments are identical
        SwapDescription memory swapDesc = SwapDescription(
            bridgeToken, bridgeToken, request.receiver, amount, amount
        );

        DstChainDescription memory dstDesc = DstChainDescription(
            request.toChainId, request.dstToken, request.expectedDstChainTokenAmount, request.slippage
        );

        // aggregator address and associated data are empty, because we only need bridging
        IYBridge(s.yBridgeAddress).swapWithReferrer{value: value}(
            LibSwapper.ETH, // aggregatorAdaptor should be 0x000 because we don't use xy adapter for swapping in source
            swapDesc,
            "0x", // The aggregatorData is empty because we don't use xy adapter for swapping in source.
            dstDesc,
            request.referrer
        );
    }

    function updateYBridgeAddressInternal(address _address) private {
        require(_address != address(0), "Invalid Gateway Address");
        YBridgeStorage storage s = getYBridgeStorage();
        address oldAddress = s.yBridgeAddress;
        s.yBridgeAddress = _address;
        emit YBridgeAddressUpdated(oldAddress, _address);
    }

    /// @dev fetch local storage
    function getYBridgeStorage() private pure returns (YBridgeStorage storage s) {
        bytes32 namespace = YBRIDGE_NAMESPACE;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            s.slot := namespace
        }
    }
}