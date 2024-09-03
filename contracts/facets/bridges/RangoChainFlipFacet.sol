// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import "../../interfaces/IRangoChainFlip.sol";
import "../../interfaces/IChainFlipBridge.sol";
import "../../interfaces/IRango.sol";
import "../../utils/ReentrancyGuard.sol";
import "../../libraries/LibSwapper.sol";
import "../../utils/LibTransform.sol";
import "../../libraries/LibDiamond.sol";
import "../../interfaces/Interchain.sol";
import "../../libraries/LibPausable.sol";

/// @title The root contract that handles Rango's interaction with ChainFlip bridge
/// @author Smnp
/// @dev This is deployed as a facet for RangoDiamond
contract RangoChainFlipFacet is IRango, ReentrancyGuard, IRangoChainFlip {
    /// Storage ///
    bytes32 internal constant CHAINFLIP_NAMESPACE = keccak256("exchange.rango.facets.ChainFlip");

    struct ChainFlipStorage {
        /// @notice is the address of chainflip vault that bridge requests are sent into
        address chainFlipValutAddress;
    }

    /// Events ///

    /// @notice Notifies that vaulta address is updated
    /// @param changedFromAddress The previous address of vault that we changed the chainFlipValutAddress from it.
    /// @param changedToAddress The new address of vault that we changed the chainFlipValutAddress to it.
    event ChainFlipVaultAddressChangedTo(address changedFromAddress, address changedToAddress);
    
    /// Initialization ///

    /// @notice Initialize the contract.
    /// @param _chainFlipVaultAddress The contract address of the vault on this chain.
    function initChainFlip(address _chainFlipVaultAddress) external {
        LibDiamond.enforceIsContractOwner();
        changeChainFlipVaultAddressInternal(_chainFlipVaultAddress);
    }

    /// @notice changes the address of vault contract
    /// @param _chainFlipVaultAddress The new contract address of the vault on this chain.
    function changeChainFlipVaultAddress(address _chainFlipVaultAddress) public {
        LibDiamond.enforceIsContractOwner();
        changeChainFlipVaultAddressInternal(_chainFlipVaultAddress);
    }

    /// @notice Executes a DEX (arbitrary) call + a ChainFlip bridge call
    /// @dev request.toToken can be address(0) for native deposits and will be replaced in doChainFlip
    /// @param request The general swap request containing from/to token and fee/affiliate rewards
    /// @param calls The list of DEX calls, if this list is empty, it means that there is no DEX call and we are only bridging
    /// @param bridgeRequest required data for the bridging step, including the destination chain and recipient wallet address
    function chainFlipSwapAndBridge(
        LibSwapper.SwapRequest memory request,
        LibSwapper.Call[] calldata calls,
        ChainFlipBridgeRequest memory bridgeRequest
    ) external payable nonReentrant {
        LibPausable.enforceNotPaused();
        uint out = LibSwapper.onChainSwapsPreBridge(request, calls, 0);
        doChainFlipBridge(bridgeRequest, request.toToken, out);

        // event emission
        emit RangoBridgeInitiated(
            request.requestId,
            request.toToken,
            out,
            LibTransform.bytesToAddress(bridgeRequest.dstAddress),
            bridgeRequest.dstChain,
            bridgeRequest.message.length > 0,
            false,
            uint8(BridgeType.ChainFlip),
            request.dAppTag,
            request.dAppName
        );
    }

    /// @notice starts bridging through ChainFlip bridge
    /// @dev request.toToken can be address(0) for native deposits and will be replaced in doChainFlipBridge
    function chainFlipBridge(
        ChainFlipBridgeRequest memory request,
        IRango.RangoBridgeRequest memory bridgeRequest
    ) external payable nonReentrant {
        LibPausable.enforceNotPaused();
        address token = bridgeRequest.token;
        uint amountWithFee = bridgeRequest.amount + LibSwapper.sumFees(bridgeRequest);
        // transfer tokens if necessary
        if (token == LibSwapper.ETH) {
            require(
                msg.value >= amountWithFee,
                "Insufficient ETH sent for bridging and fees"
                );
        } else {
            SafeERC20.safeTransferFrom(IERC20(token), msg.sender, address(this), amountWithFee);
        }
        LibSwapper.collectFees(bridgeRequest);
        doChainFlipBridge(request, token, bridgeRequest.amount);

        // event emission
        emit RangoBridgeInitiated(
            bridgeRequest.requestId,
            token,
            bridgeRequest.amount,
            LibTransform.bytesToAddress(request.dstAddress),
            request.dstChain,
            request.message.length > 0,
            false,
            uint8(BridgeType.ChainFlip),
            bridgeRequest.dAppTag,
            bridgeRequest.dAppName
        );
    }

    /// @notice Executes an ChainFlip bridge call
    /// @dev request.dstToken can be 0xEeee...eeEEeE for native deposits
    /// @param request The other required fields for ChainFlip bridge contract
    /// @param amount Amount of tokens to deposit. Will be amount of tokens to receive less fees.
    function doChainFlipBridge(
        ChainFlipBridgeRequest memory request,
        address token,
        uint amount
    ) internal {

        ChainFlipStorage storage s = getChainFlipStorage();

        if(request.message.length > 0){
            if(token == LibSwapper.ETH) {
                IChainFlipBridge(s.chainFlipValutAddress).xCallNative{value: amount}(
                    request.dstChain,
                    request.dstAddress,
                    request.dstToken,
                    request.message,
                    request.gasAmount,
                    request.cfParameters
                );
            } else {
                LibSwapper.approveMax(token, s.chainFlipValutAddress, amount);
                IChainFlipBridge(s.chainFlipValutAddress).xCallToken(
                    request.dstChain,
                    request.dstAddress,
                    request.dstToken,
                    request.message,
                    request.gasAmount,
                    request.srcToken,
                    amount,
                    request.cfParameters
                );
            }
        }else{
            if(token == LibSwapper.ETH) {
                IChainFlipBridge(s.chainFlipValutAddress).xSwapNative{value: amount}(
                    request.dstChain,
                    request.dstAddress,
                    request.dstToken,
                    request.cfParameters
                );
            } else {
                LibSwapper.approveMax(token, s.chainFlipValutAddress, amount);
                IChainFlipBridge(s.chainFlipValutAddress).xSwapToken(
                    request.dstChain,
                    request.dstAddress,
                    request.dstToken,
                    request.srcToken,
                    amount,
                    request.cfParameters
                );
            }
        }
    }

    function changeChainFlipVaultAddressInternal(address _newChainFlipVaultAddress) private {
        ChainFlipStorage storage s = getChainFlipStorage();
        address previousVaultAddress = s.chainFlipValutAddress;
        require(_newChainFlipVaultAddress != address(0), "Invalid VaultAddress Address");
        s.chainFlipValutAddress = _newChainFlipVaultAddress;
        emit ChainFlipVaultAddressChangedTo(previousVaultAddress, _newChainFlipVaultAddress);
    }

    /// @dev fetch local storage
    function getChainFlipStorage() private pure returns (ChainFlipStorage storage s) {
        bytes32 namespace = CHAINFLIP_NAMESPACE;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            s.slot := namespace
        }
    }
}