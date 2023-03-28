// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.16;

import "../../interfaces/IRangoVoyager.sol";
import "../../interfaces/IVoyager.sol";
import "../../interfaces/IRango.sol";
import "../../utils/ReentrancyGuard.sol";
import "../../utils/LibTransform.sol";
import "../../libraries/LibInterchain.sol";
import "../../libraries/LibDiamond.sol";

// @title Facet contract to interact with Voyager bridge.
// @dev In current version, paying bridge fees is only possible with native token. (only depositETH is implemented)
contract RangoVoyagerFacet is IRango, ReentrancyGuard, IRangoVoyager {
    /// Storage ///
    /// @dev keccak256("exchange.rango.facets.voyager")
    bytes32 internal constant VOYAGER_NAMESPACE = hex"2237235c23b61f52702df59dac601909c9db9f9eb24657d730ec4417623a598e";

    struct VoyagerStorage {
        address routerBridgeAddress;
        address reserveHandlerAddress;
        address voyagerSpecificNativeWrappedAddress;
    }

    /// Events ///

    /// @notice Emits when the Voyager address is updated
    /// @param _oldAddress The previous address
    /// @param _newAddress The new address
    event RouterBridgeAddressUpdated(address _oldAddress, address _newAddress);
    /// @notice Emits when the Voyager address is updated
    /// @param _oldAddress The previous address
    /// @param _newAddress The new address
    event ReserveHandlerAddressUpdated(address _oldAddress, address _newAddress);

    /// @notice Initialize the contract.
    /// @param voyagerAddresses The address of WETH, WBNB, etc of the current network plus voyager contract address
    function initVoyager(VoyagerStorage calldata voyagerAddresses) external {
        LibDiamond.enforceIsContractOwner();
        updateRouterBridgeAddressInternal(voyagerAddresses.routerBridgeAddress);
        updateReserveHandlerAddressInternal(voyagerAddresses.reserveHandlerAddress);
        updateVoyagerSpecificNativeWrappedAddressInternal(voyagerAddresses.voyagerSpecificNativeWrappedAddress);
    }

    /// @notice update routerBridgeAddress
    /// @param _address routerBridgeAddress
    function updateVoyagerRouters(address _address) public {
        LibDiamond.enforceIsContractOwner();
        updateRouterBridgeAddressInternal(_address);
    }

    /// @notice update reserveHandler
    /// @param _address reserveHandler
    function updateVoyagerReserveHandler(address _address) public {
        LibDiamond.enforceIsContractOwner();
        updateReserveHandlerAddressInternal(_address);
    }

    /// @notice update voyagerSpecificNativeWrappedAddress
    /// @param _address voyagerSpecificNativeWrappedAddress
    function updateVoyagerSpecificNativeWrappedAddress(address _address) public {
        LibDiamond.enforceIsContractOwner();
        updateVoyagerSpecificNativeWrappedAddressInternal(_address);
    }

    function voyagerSwapAndBridge(
        LibSwapper.SwapRequest memory request,
        LibSwapper.Call[] calldata calls,
        IRangoVoyager.VoyagerBridgeRequest memory bridgeRequest
    ) external payable nonReentrant {
        uint out;
        uint bridgeAmount;
        // if toToken is native coin and the user has not paid fee in msg.value,
        // then the user can pay bridge fee using output of swap.
        if (request.toToken == LibSwapper.ETH && msg.value == 0) {
            out = LibSwapper.onChainSwapsPreBridge(request, calls, 0);
            bridgeAmount = out - bridgeRequest.feeAmount;
        }
        else {
            out = LibSwapper.onChainSwapsPreBridge(request, calls, bridgeRequest.feeAmount);
            bridgeAmount = out;
        }

        doVoyagerBridge(bridgeRequest, request.toToken, bridgeAmount);

        // event emission
        emit RangoBridgeInitiated(
            request.requestId,
            request.toToken,
            bridgeAmount,
            LibSwapper.ETH, // receiver is embedded in data and we dont extract it for event emission
            bridgeRequest.voyagerDestinationChainId,
            false,
            false,
            uint8(BridgeType.Voyager),
            request.dAppTag
        );
    }

    function voyagerBridge(
        IRangoVoyager.VoyagerBridgeRequest memory request,
        IRango.RangoBridgeRequest memory bridgeRequest
    ) external payable nonReentrant {
        uint amount = bridgeRequest.amount;
        address token = bridgeRequest.token;
        uint amountWithFee = amount + LibSwapper.sumFees(bridgeRequest);
        // transfer tokens if necessary
        if (token != LibSwapper.ETH) {
            SafeERC20.safeTransferFrom(IERC20(token), msg.sender, address(this), amountWithFee);
            require(msg.value >= request.feeAmount, "Insufficient ETH for fee");
        } else {
            require(msg.value >= amountWithFee + request.feeAmount, "Insufficient ETH for bridging and fee");
        }
        LibSwapper.collectFees(bridgeRequest);
        doVoyagerBridge(request, token, bridgeRequest.amount);

        // event emission
        emit RangoBridgeInitiated(
            bridgeRequest.requestId,
            token,
            amount,
            LibSwapper.ETH, // receiver is embedded in data and we dont extract it for event emission
            request.voyagerDestinationChainId,
            false,
            false,
            uint8(BridgeType.Voyager),
            bridgeRequest.dAppTag
        );
    }

    /// @notice Executes an Voyager bridge call
    /// @param request The other required fields for Voyager bridge contract
    /// @param fromToken The erc20 address of the input token, 0x000...00 for native token
    /// @param amount Amount of tokens to deposit. Will be amount of tokens to receive less fees.
    function doVoyagerBridge(
        VoyagerBridgeRequest memory request,
        address fromToken,
        uint256 amount
    ) internal {
        VoyagerStorage storage s = getVoyagerStorage();
        address weth = s.voyagerSpecificNativeWrappedAddress;
        require(request.feeTokenAddress == weth,
            "Fee is only acceptable in native token in current version");
        uint approveAmount = request.feeAmount;
        if (fromToken != LibSwapper.ETH) {
            LibSwapper.approveMax(fromToken, s.reserveHandlerAddress, amount);
        } else {
            approveAmount = amount + approveAmount;
        }
        LibSwapper.approveMax(request.feeTokenAddress, s.reserveHandlerAddress, approveAmount);

        IVoyager voyager = IVoyager(s.routerBridgeAddress);

        callVoyager(voyager, request, fromToken, amount);
    }

    function callVoyager(
        IVoyager voyager,
        VoyagerBridgeRequest memory request,
        address fromToken,
        uint256 amount
    ) private {
        bytes memory encodedParams = bytes.concat(
            abi.encode(
                amount,
                amount,
                request.dstTokenAmount,
                request.dstTokenAmount
            ), request.data
        );

        uint256[] memory flags;
        address[] memory path;
        bytes[] memory dataTx;

        voyager.depositETH{value : fromToken == LibSwapper.ETH ? amount + request.feeAmount : request.feeAmount}(
            request.voyagerDestinationChainId,
            request.resourceID,
            encodedParams,
            flags, path, dataTx,
            request.feeTokenAddress
        );
    }

    function updateRouterBridgeAddressInternal(address _address) private {
        VoyagerStorage storage s = getVoyagerStorage();
        address oldAddress = s.routerBridgeAddress;
        s.routerBridgeAddress = _address;
        emit RouterBridgeAddressUpdated(oldAddress, _address);
    }

    function updateReserveHandlerAddressInternal(address _address) private {
        VoyagerStorage storage s = getVoyagerStorage();
        address oldAddress = s.reserveHandlerAddress;
        s.reserveHandlerAddress = _address;
        emit ReserveHandlerAddressUpdated(oldAddress, _address);
    }

    function updateVoyagerSpecificNativeWrappedAddressInternal(address _address) private {
        require(_address != address(0), "Invalid Wrapped Address");
        VoyagerStorage storage s = getVoyagerStorage();
        address oldAddress = s.voyagerSpecificNativeWrappedAddress;
        s.voyagerSpecificNativeWrappedAddress = _address;
        emit ReserveHandlerAddressUpdated(oldAddress, _address);
    }

    /// @dev fetch local storage
    function getVoyagerStorage() private pure returns (VoyagerStorage storage s) {
        bytes32 namespace = VOYAGER_NAMESPACE;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            s.slot := namespace
        }
    }
}