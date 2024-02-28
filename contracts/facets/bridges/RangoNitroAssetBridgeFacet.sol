// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.16;

import "../../interfaces/IRangoNitroAssetBridge.sol";
import "../../interfaces/IRango.sol";
import "../../utils/ReentrancyGuard.sol";
import "../../utils/LibTransform.sol";
import "../../libraries/LibInterchain.sol";
import "../../libraries/LibDiamond.sol";
import "../../interfaces/IRouterNitroAssetBridge.sol";
import "../../interfaces/IRouterGateway.sol";

// @title Facet contract to interact with Router Nitro Asset Bridge
contract RangoNitroAssetBridgeFacet is
    IRango,
    ReentrancyGuard,
    IRangoNitroAssetBridge
{
    /// Storage ///
    /// @dev keccak256("exchange.rango.facets.nitro_asset_bridge")
    bytes32 internal constant NITRO_ASSET_BRIDGE_NAMESPACE =
        hex"5653c4393a800c1728e2b1c180a479965b6868110b62dc21d27cdc58e743c798";

    address internal constant NATIVE =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    struct NitroStorage {
        address nitroAssetBridge;
        address routerGateway;
    }

    /// Events ///

    /// @notice Emits when the Nitro Asset Bridge address is updated
    /// @param _oldAddress The previous address
    /// @param _newAddress The new address
    event NitroAssetBridgeAddressUpdated(
        address _oldAddress,
        address _newAddress
    );
    /// @notice Emits when the Router Gateway address is updated
    /// @param _oldAddress The previous address
    /// @param _newAddress The new address
    event RouterGatewayAddressUpdated(address _oldAddress, address _newAddress);

    /// @notice Initialize the contract.
    /// @param nitroAddresses The address of WETH, WBNB, etc of the current network plus nitro contract address
    function initRouterNitro(NitroStorage calldata nitroAddresses) external {
        LibDiamond.enforceIsContractOwner();
        updateNitroAssetBridgeAddressInternal(nitroAddresses.nitroAssetBridge);
        updateRouterGatewayAddressInternal(nitroAddresses.routerGateway);
    }

    /// @notice update nitroAssetBridge address
    /// @param _address nitroAssetBridge address
    function updateNitroAssetBridge(address _address) public {
        LibDiamond.enforceIsContractOwner();
        updateNitroAssetBridgeAddressInternal(_address);
    }

    /// @notice update routerGateway address
    /// @param _address routerGateway address
    function updateRouterGateway(address _address) public {
        LibDiamond.enforceIsContractOwner();
        updateRouterGatewayAddressInternal(_address);
    }

    function nitroSwapAndBridge(
        LibSwapper.SwapRequest memory request,
        LibSwapper.Call[] calldata calls,
        IRangoNitroAssetBridge.NitroBridgeRequest memory bridgeRequest
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
            uint8(BridgeType.NitroAssetBridge),
            request.dAppTag
        );
    }

    function nitroBridge(
        IRangoNitroAssetBridge.NitroBridgeRequest memory request,
        IRango.RangoBridgeRequest memory bridgeRequest
    ) external payable nonReentrant {
        uint amount = bridgeRequest.amount;
        address token = bridgeRequest.token;
        uint amountWithFee = amount + LibSwapper.sumFees(bridgeRequest);
        // transfer tokens if necessary
        SafeERC20.safeTransferFrom(
            IERC20(token),
            msg.sender,
            address(this),
            amountWithFee
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
            uint8(BridgeType.NitroAssetBridge),
            bridgeRequest.dAppTag
        );
    }

    /// @notice Executes an Nitro bridge call
    /// @param request The other required fields for Nitro bridge contract
    /// @param fromToken The erc20 address of the input token, 0x000...00 for native token
    /// @param amount Amount of tokens to deposit. Will be amount of tokens to receive less fees.
    function doNitroBridge(
        IRangoNitroAssetBridge.NitroBridgeRequest memory request,
        address fromToken,
        uint256 amount
    ) internal {
        NitroStorage storage s = getNitroStorage();
        IRouterGateway routerGateway = IRouterGateway(s.routerGateway);
        IRouterNitroAssetBridge nitroAssetBridge = IRouterNitroAssetBridge(
            s.nitroAssetBridge
        );

        callNitro(routerGateway, nitroAssetBridge, request, fromToken, amount);
    }

    function callNitro(
        IRouterGateway routerGateway,
        IRouterNitroAssetBridge nitroAssetBridge,
        IRangoNitroAssetBridge.NitroBridgeRequest memory request,
        address fromToken,
        uint256 amount
    ) private {
        IRouterNitroAssetBridge.TransferPayload
            memory transferPayload = IRouterNitroAssetBridge.TransferPayload({
                destChainIdBytes: getChainIdBytes(request.destChainId),
                srcTokenAddress: fromToken,
                srcTokenAmount: amount,
                recipient: request.recipient,
                partnerId: request.partnerId
            });

        uint256 iSendFee = routerGateway.iSendDefaultFee();
        LibSwapper.approveMax(fromToken, address(nitroAssetBridge), amount);

        if (request.message.length == 0)
            nitroAssetBridge.transferToken{value: iSendFee}(transferPayload);
        else
            nitroAssetBridge.transferTokenWithInstruction{value: iSendFee}(
                transferPayload,
                request.destGasLimit,
                request.message
            );
    }

    function updateNitroAssetBridgeAddressInternal(address _address) private {
        NitroStorage storage s = getNitroStorage();
        address oldAddress = s.nitroAssetBridge;
        s.nitroAssetBridge = _address;
        emit NitroAssetBridgeAddressUpdated(oldAddress, _address);
    }

    function updateRouterGatewayAddressInternal(address _address) private {
        NitroStorage storage s = getNitroStorage();
        address oldAddress = s.routerGateway;
        s.routerGateway = _address;
        emit RouterGatewayAddressUpdated(oldAddress, _address);
    }

    /// @dev fetch local storage
    function getNitroStorage() private pure returns (NitroStorage storage s) {
        bytes32 namespace = NITRO_ASSET_BRIDGE_NAMESPACE;
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
