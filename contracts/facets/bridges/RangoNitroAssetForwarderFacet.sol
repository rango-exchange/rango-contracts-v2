// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.16;

import "../../interfaces/IRangoNitroAssetForwarder.sol";
import "../../interfaces/IRango.sol";
import "../../utils/ReentrancyGuard.sol";
import "../../utils/LibTransform.sol";
import "../../libraries/LibInterchain.sol";
import "../../libraries/LibDiamond.sol";
import "../../interfaces/IRouterNitroAssetForwarder.sol";

// @title Facet contract to interact with Router Nitro Asset Forwarder
contract RangoNitroAssetForwarderFacet is
    IRango,
    ReentrancyGuard,
    IRangoNitroAssetForwarder
{
    /// Storage ///
    /// @dev keccak256("exchange.rango.facets.nitro_asset_forwarder")
    bytes32 internal constant NITRO_ASSET_FORWARDER_NAMESPACE =
        hex"ebac9d4b86564e454526189ad2e663764ca42d40bf0dc77efceebc2eba5ef994";

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
        IRangoNitroAssetForwarder.NitroBridgeRequest memory bridgeRequest
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
            uint8(BridgeType.NitroAssetForwarder),
            request.dAppTag
        );
    }

    function nitroBridge(
        IRangoNitroAssetForwarder.NitroBridgeRequest memory request,
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
            uint8(BridgeType.NitroAssetForwarder),
            bridgeRequest.dAppTag
        );
    }

    /// @notice Executes an Nitro bridge call
    /// @param request The other required fields for Nitro bridge contract
    /// @param fromToken The erc20 address of the input token, 0x000...00 for native token
    /// @param amount Amount of tokens to deposit. Will be amount of tokens to receive less fees.
    function doNitroBridge(
        IRangoNitroAssetForwarder.NitroBridgeRequest memory request,
        address fromToken,
        uint256 amount
    ) internal {
        NitroStorage storage s = getNitroStorage();
        IRouterNitroAssetForwarder nitroAssetForwarder = IRouterNitroAssetForwarder(
                s.nitroAssetForwarder
            );

        callNitro(nitroAssetForwarder, request, fromToken, amount);
    }

    function callNitro(
        IRouterNitroAssetForwarder nitroAssetForwarder,
        IRangoNitroAssetForwarder.NitroBridgeRequest memory request,
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

        if (request.message.length == 0)
            nitroAssetForwarder.iDeposit{
                value: fromToken == LibSwapper.ETH ? amount : 0
            }(depositData, request.destToken, request.recipient);
        else
            nitroAssetForwarder.iDepositMessage{
                value: fromToken == LibSwapper.ETH ? amount : 0
            }(
                depositData,
                request.destToken,
                request.recipient,
                request.message
            );
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
        bytes32 namespace = NITRO_ASSET_FORWARDER_NAMESPACE;
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
