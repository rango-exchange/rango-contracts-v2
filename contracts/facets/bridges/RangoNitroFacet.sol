// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.16;

import "../../interfaces/IRangoNitro.sol";
import "../../interfaces/IRango.sol";
import "../../utils/ReentrancyGuard.sol";
import "../../utils/LibTransform.sol";
import "../../libraries/LibInterchain.sol";
import "../../libraries/LibDiamond.sol";
import "../../interfaces/IRouterNitroAssetForwarder.sol";

// @title Facet contract to interact with Router Nitro bridge.
// @dev In current version, paying bridge fees is only possible with native token. (only depositETH is implemented)
contract RangoNitroFacet is IRango, ReentrancyGuard, IRangoNitro {
    /// Storage ///
    /// @dev keccak256("exchange.rango.facets.nitro")
    bytes32 internal constant NITRO_NAMESPACE =
        hex"edbe4e8157d924fac5c418d6ed7f8d60f649675f1453d98af6e0f035b57ff730";

    address internal constant NATIVE =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    struct NitroStorage {
        address nitroAssetForwarder;
    }

    /// Events ///

    /// @notice Emits when the Nitro asset forwarder address is updated
    /// @param _oldAddress The previous address
    /// @param _newAddress The new address
    event NitroAssetForwarderAddressUpdated(
        address _oldAddress,
        address _newAddress
    );

    /// @notice Initialize the contract.
    /// @param nitroAddresses The address of WETH, WBNB, etc of the current network plus nitro contract address
    function initRouterNitro(NitroStorage calldata nitroAddresses) external {
        LibDiamond.enforceIsContractOwner();
        updateNitroAssetForwarderAddressInternal(
            nitroAddresses.nitroAssetForwarder
        );
    }

    /// @notice update nitroAssetForwarder address
    /// @param _address nitroAssetForwarder address
    function updateNitroAssetForwarder(address _address) public {
        LibDiamond.enforceIsContractOwner();
        updateNitroAssetForwarderAddressInternal(_address);
    }

    function nitroSwapAndBridge(
        LibSwapper.SwapRequest memory request,
        LibSwapper.Call[] calldata calls,
        IRangoNitro.NitroBridgeRequest memory bridgeRequest
    ) external payable nonReentrant {
        uint bridgeAmount = LibSwapper.onChainSwapsPreBridge(request, calls, 0);

        doNitroBridge(bridgeRequest, request.toToken, bridgeAmount);

        // event emission
        emit RangoBridgeInitiated(
            request.requestId,
            request.toToken,
            bridgeAmount,
            LibSwapper.ETH, // receiver is embedded in data and we dont extract it for event emission
            uint256(getChainIdBytes(bridgeRequest.destChainId)),
            false,
            false,
            uint8(BridgeType.Nitro),
            request.dAppTag
        );
    }

    function nitroBridge(
        IRangoNitro.NitroBridgeRequest memory request,
        IRango.RangoBridgeRequest memory bridgeRequest
    ) external payable nonReentrant {
        uint amount = bridgeRequest.amount;
        address token = bridgeRequest.token;
        uint amountWithFee = amount + LibSwapper.sumFees(bridgeRequest);
        // transfer tokens if necessary
        if (token != LibSwapper.ETH)
            SafeERC20.safeTransferFrom(
                IERC20(token),
                msg.sender,
                address(this),
                amountWithFee
            );
        else
            require(
                msg.value >= amountWithFee,
                "Insufficient ETH for bridging"
            );

        LibSwapper.collectFees(bridgeRequest);
        doNitroBridge(request, token, bridgeRequest.amount);

        // event emission
        emit RangoBridgeInitiated(
            bridgeRequest.requestId,
            token,
            amount,
            LibSwapper.ETH, // receiver is embedded in data and we dont extract it for event emission
            uint256(getChainIdBytes(request.destChainId)),
            false,
            false,
            uint8(BridgeType.Nitro),
            bridgeRequest.dAppTag
        );
    }

    /// @notice Executes an Nitro bridge call
    /// @param request The other required fields for Nitro bridge contract
    /// @param fromToken The erc20 address of the input token, 0x000...00 for native token
    /// @param amount Amount of tokens to deposit. Will be amount of tokens to receive less fees.
    function doNitroBridge(
        IRangoNitro.NitroBridgeRequest memory request,
        address fromToken,
        uint256 amount
    ) internal {
        NitroStorage storage s = getNitroStorage();

        if (fromToken != LibSwapper.ETH)
            LibSwapper.approveMax(fromToken, s.nitroAssetForwarder, amount);

        IRouterNitroAssetForwarder nitroAssetForwarder = IRouterNitroAssetForwarder(
                s.nitroAssetForwarder
            );

        callNitro(nitroAssetForwarder, request, fromToken, amount);
    }

    function callNitro(
        IRouterNitroAssetForwarder nitroAssetForwarder,
        IRangoNitro.NitroBridgeRequest memory request,
        address fromToken,
        uint256 amount
    ) private {
        IRouterNitroAssetForwarder.DepositData
            memory depositData = IRouterNitroAssetForwarder.DepositData({
                partnerId: request.partnerId,
                amount: amount,
                destAmount: request.destAmount,
                srcToken: fromToken == LibSwapper.ETH ? NATIVE : fromToken,
                refundRecipient: request.refundRecipient,
                destChainIdBytes: getChainIdBytes(request.destChainId)
            });

        if (fromToken != LibSwapper.ETH)
            LibSwapper.approveMax(
                fromToken,
                address(nitroAssetForwarder),
                amount
            );

        nitroAssetForwarder.iDeposit{
            value: fromToken == LibSwapper.ETH ? amount : 0
        }(depositData, request.destToken, request.recipient);
    }

    function updateNitroAssetForwarderAddressInternal(
        address _address
    ) private {
        NitroStorage storage s = getNitroStorage();
        address oldAddress = s.nitroAssetForwarder;
        s.nitroAssetForwarder = _address;
        emit NitroAssetForwarderAddressUpdated(oldAddress, _address);
    }

    /// @dev fetch local storage
    function getNitroStorage() private pure returns (NitroStorage storage s) {
        bytes32 namespace = NITRO_NAMESPACE;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            s.slot := namespace
        }
    }

    function getChainIdBytes(
        string memory _chainId
    ) public pure returns (bytes32) {
        bytes32 chainIdBytes32;

        // solhint-disable-next-line no-inline-assembly
        assembly {
            chainIdBytes32 := mload(add(_chainId, 32))
        }

        return chainIdBytes32;
    }
}
