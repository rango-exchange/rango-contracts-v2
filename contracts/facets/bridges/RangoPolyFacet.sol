// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.16;

import "../../interfaces/IWETH.sol";
import "../../interfaces/IRangoPoly.sol";
import "../../interfaces/IRango.sol";
import "../../interfaces/IPolyBridge.sol";
import "../../utils/ReentrancyGuard.sol";
import "../../libraries/LibSwapper.sol";
import "../../libraries/LibDiamond.sol";

/// @title The root contract that handles Rango's interaction with poly
/// @author AMA
contract RangoPolyFacet is IRango, ReentrancyGuard, IRangoPoly {

    /// Storage ///
    /// @dev keccak256("exchange.rango.facets.poly")
    bytes32 internal constant POLY_NAMESPACE = hex"dd09bd052dafcb281d30e61963e3b07fe83d05bbb2a522b1413909ef339380a7";

    struct PolyStorage {
        /// @notice The address of poly contract
        address polyWrapperAddress;
    }

    /// @notice Emits when the poly address is updated
    /// @param _oldAddress The previous address
    /// @param _newAddress The new address
    event PolyAddressUpdated(address _oldAddress, address _newAddress);

    /// @notice Initialize the contract.
    /// @param polyWrapperAddress The contract address of poly contract.
    function initPoly(address polyWrapperAddress) external {
        LibDiamond.enforceIsContractOwner();
        updatePolyAddressInternal(polyWrapperAddress);
    }

    /// @notice Emits when an token (non-native) bridge request is sent to poly bridge
    /// @param dstChainId The network id of destination chain, ex: 56 for BSC
    /// @param token The requested token to bridge
    /// @param receiver The receiver address in the destination chain
    /// @param amount The requested amount to bridge
    /// @param fee The requested amount to pay for bridge fee
    event PolyDeposit(uint64 dstChainId, address token, address receiver, uint256 amount, uint256 fee);

    /// @notice Executes a DEX (arbitrary) call + a poly bridge function
    /// @param request The general swap request containing from/to token and fee/affiliate rewards
    /// @param calls The list of DEX calls, if this list is empty, it means that there is no DEX call and we are only bridging
    /// @param bridgeRequest data related to poly bridge
    /// @dev If this function is a success, user will automatically receive the fund in the destination in their wallet (receiver)
    function polySwapAndBridge(
        LibSwapper.SwapRequest memory request,
        LibSwapper.Call[] calldata calls,
        IRangoPoly.PolyBridgeRequest memory bridgeRequest
    ) external payable nonReentrant {
        uint out;
        uint bridgeAmount;

        // if toToken is native coin and the user has not paid fee in msg.value,
        // then the user can pay bridge fee using output of swap.
        if (request.toToken == LibSwapper.ETH && msg.value == 0) {
            out = LibSwapper.onChainSwapsPreBridge(request, calls, 0);
            bridgeAmount = out - bridgeRequest.fee;
        }
        else {
            out = LibSwapper.onChainSwapsPreBridge(request, calls, bridgeRequest.fee);
            bridgeAmount = out;
        }

        doPolyBridge(bridgeRequest, request.toToken, bridgeAmount);

        // event emission
        emit RangoBridgeInitiated(
            request.requestId,
            request.toToken,
            out,
            bridgeRequest.receiver,
            bridgeRequest.toChainId,
            false,
            false,
            uint8(BridgeType.Poly),
            request.dAppTag
        );
    }

    /// @notice Executes a poly bridge function
    /// @param request data related to poly bridge
    /// @param bridgeRequest data related to poly bridge
    function polyBridge(
        IRangoPoly.PolyBridgeRequest memory request,
        IRango.RangoBridgeRequest memory bridgeRequest
    ) external payable nonReentrant {
        uint256 amountWithFee = bridgeRequest.amount + LibSwapper.sumFees(bridgeRequest);
        // transfer tokens if necessary
        if (bridgeRequest.token == LibSwapper.ETH) {
            require(msg.value >= amountWithFee + request.fee, "Insufficient ETH sent for bridging");
        } else {
            require(msg.value >= request.fee, "Insufficient ETH sent for bridging");
            SafeERC20.safeTransferFrom(IERC20(bridgeRequest.token), msg.sender, address(this), amountWithFee);
        }

        LibSwapper.collectFees(bridgeRequest);
        doPolyBridge(request, bridgeRequest.token, bridgeRequest.amount);

        // event emission
        emit RangoBridgeInitiated(
            bridgeRequest.requestId,
            bridgeRequest.token,
            bridgeRequest.amount,
            request.receiver,
            request.toChainId,
            false,
            false,
            uint8(BridgeType.Poly),
            bridgeRequest.dAppTag
        );
    }

    /// @notice Executes a bridging via poly
    /// @param request The extra fields required by the poly bridge
    /// @param token The requested token to bridge
    /// @param amount The requested amount to bridge
    function doPolyBridge(
        PolyBridgeRequest memory request,
        address token,
        uint256 amount
    ) internal {
        PolyStorage storage s = getPolyStorage();
        bytes memory receiver = addressToBytes(request.receiver);
        uint64 dstChainId = request.toChainId;

        require(s.polyWrapperAddress != LibSwapper.ETH, 'Poly address not set');
        require(block.chainid != dstChainId, 'Cannot bridge to the same network');

        if (token == LibSwapper.ETH) {
            IPolyBridge(s.polyWrapperAddress).lock{value : request.fee + amount}(
                token,
                dstChainId,
                receiver,
                amount + request.fee,
                request.fee,
                request.id
            );
        } else {
            LibSwapper.approve(token, s.polyWrapperAddress, amount);
            IPolyBridge(s.polyWrapperAddress).lock{value : request.fee}(
                token,
                dstChainId,
                receiver,
                amount,
                request.fee,
                request.id
            );
        }

        emit PolyDeposit(dstChainId, token, request.receiver, amount, request.fee);
    }

    /* @notice      Convert bytes to address
    *  @param _bs   Source bytes: bytes length must be 20
    *  @return      Converted address from source bytes
    */
    function bytesToAddress(bytes memory _bs) internal pure returns (address addr)
    {
        require(_bs.length == 20, "bytes length does not match address");
        assembly {
            // for _bs, first word store _bs.length, second word store _bs.value
            // load 32 bytes from mem[_bs+20], convert it into Uint160, meaning we take last 20 bytes as addr (address).
            addr := mload(add(_bs, 0x14))
        }

    }

    /* @notice      Convert address to bytes
    *  @param _addr Address need to be converted
    *  @return      Converted bytes from address
    */
    function addressToBytes(address _addr) internal pure returns (bytes memory bs){
        assembly {
            // Get a location of some free memory and store it in result as
            // Solidity does for memory variables.
            bs := mload(0x40)
            // Put 20 (address byte length) at the first word, the length of bytes for uint256 value
            mstore(bs, 0x14)
            // logical shift left _a by 12 bytes, change _a from right-aligned to left-aligned
            mstore(add(bs, 0x20), shl(96, _addr))
            // Update the free-memory pointer by padding our last write location to 32 bytes
            mstore(0x40, add(bs, 0x40))
       }
    }

    function updatePolyAddressInternal(address _address) private {
        require(_address != address(0), "Invalid Poly Address");
        PolyStorage storage s = getPolyStorage();
        address oldAddress = s.polyWrapperAddress;
        s.polyWrapperAddress = _address;
        emit PolyAddressUpdated(oldAddress, _address);
    }

    /// @dev fetch local storage
    function getPolyStorage() private pure returns (PolyStorage storage s) {
        bytes32 namespace = POLY_NAMESPACE;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            s.slot := namespace
        }
    }
}