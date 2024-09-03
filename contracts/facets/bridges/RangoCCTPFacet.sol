// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import "../../interfaces/IRangoCCTP.sol";
import "../../interfaces/IRango.sol";
import "../../interfaces/ICCTPTokenMassenger.sol";
import "../../utils/ReentrancyGuard.sol";
import "../../libraries/LibSwapper.sol";
import "../../libraries/LibDiamond.sol";
import "../../utils/LibTransform.sol";
import "../../libraries/LibPausable.sol";

/// @title The root contract that handles Rango's interaction with Cross-Chain Transfer Protocol (circle)
/// @author Thinking Particle
/// @dev This is deployed as a facet for RangoDiamond
contract RangoCCTPFacet is IRango, ReentrancyGuard, IRangoCCTP {
    /// Storage ///
    bytes32 internal constant CCTP_NAMESPACE = keccak256("exchange.rango.facets.cctp");

    struct CCTPStorage {
        /// @notice contract to initiate cross chain swap
        address tokenMessenger;
        /// @notice USDC token address in current chain
        address USDCTokenAddress;
    }

    /// @notice Emitted when the cctp tokenMessenger address is updated
    /// @param _oldAddress The previous address
    /// @param _newAddress The new address
    event CCTPTokenMessengerAddressUpdated(address _oldAddress, address _newAddress);
    /// @notice Emitted when the USDC Token address is updated
    /// @param _oldAddress The previous address
    /// @param _newAddress The new address
    event CCTPUSDCTokenAddressUpdated(address _oldAddress, address _newAddress);

    /// @notice An event showing that a CCTP bridge call to deposit and burn happened
    event CCTPBridgeDepositAndBurnDone(
        uint32 destinationDomainId,
        bytes32 recipient,
        address token,
        uint amount
    );

    /// @notice Initialize the contract.
    /// @param _tokenMessenger The token messenger address of Circle CCTP in this chain
    /// @param _usdcTokenAddress The token address of Circle USDC in this chain
    function initCCTP(address _tokenMessenger, address _usdcTokenAddress) external {
        LibDiamond.enforceIsContractOwner();
        updateCCTPTokenMessengerInternal(_tokenMessenger);
        updateCCTPUSDCTokenAddressInternal(_usdcTokenAddress);
    }

    /// @notice Updates the address of CCTP tokenMessenger contract
    /// @param _address The new address of CCTP tokenMessenger contract
    function updateCCTPTokenMessengerAddress(address _address) public {
        LibDiamond.enforceIsContractOwner();
        updateCCTPTokenMessengerInternal(_address);
    }

    /// @notice Updates the address of USDC Token
    /// @param _address The new address of USDC Token
    function updateCCTPUSDCTokenAddress(address _address) public {
        LibDiamond.enforceIsContractOwner();
        updateCCTPUSDCTokenAddressInternal(_address);
    }

    /// @notice Executes a DEX (arbitrary) call + a CCTP bridge transaction
    /// @dev request.toToken can be address(0) for native deposits and will be replaced in doAcrossBridge
    /// @param request The general swap request containing from/to token and fee/affiliate rewards
    /// @param calls The list of DEX calls, if this list is empty, it means that there is no DEX call and we are only bridging
    /// @param bridgeRequest required data for the bridging step, including the destination chain and recipient wallet address
    function cctpSwapAndBridge(
        LibSwapper.SwapRequest memory request,
        LibSwapper.Call[] calldata calls,
        CCTPRequest memory bridgeRequest
    ) external payable nonReentrant {
        LibPausable.enforceNotPaused();
        uint out = LibSwapper.onChainSwapsPreBridge(request, calls, 0);

        doCctpBridge(bridgeRequest, request.toToken, out);

        // event emission
        emit RangoBridgeInitiated(
            request.requestId,
            request.toToken,
            out,
            LibTransform.bytes32LeftPaddedToAddress(bridgeRequest.recipient),
            bridgeRequest.destinationChainId,
            false,
            false,
            uint8(BridgeType.CCTP),
            request.dAppTag,
            request.dAppName
        );
    }

    /// @notice Executes bridging via CCTP
    /// @param request The extra fields required by the CCTP bridge
    function cctpBridge(
        CCTPRequest memory request,
        RangoBridgeRequest memory bridgeRequest
    ) external payable nonReentrant {
        LibPausable.enforceNotPaused();
        uint256 amountWithFee = bridgeRequest.amount + LibSwapper.sumFees(bridgeRequest);

        SafeERC20.safeTransferFrom(IERC20(bridgeRequest.token), msg.sender, address(this), amountWithFee);

        LibSwapper.collectFees(bridgeRequest);
        doCctpBridge(request, bridgeRequest.token, bridgeRequest.amount);

        // event emission
        emit RangoBridgeInitiated(
            bridgeRequest.requestId,
            bridgeRequest.token,
            bridgeRequest.amount,
            LibTransform.bytes32LeftPaddedToAddress(request.recipient),
            request.destinationChainId,
            false,
            false,
            uint8(BridgeType.CCTP),
            bridgeRequest.dAppTag,
            bridgeRequest.dAppName
        );
    }

    function doCctpBridge(
        CCTPRequest memory request,
        address token,
        uint amount
    ) internal {
        CCTPStorage storage s = getCCTPStorage();
        require(s.tokenMessenger != LibSwapper.ETH, 'CCTP tokenMessenger address not set');
        require(block.chainid != request.destinationChainId, 'Invalid destination Chain! Cannot bridge to the same network.');
        require(token == s.USDCTokenAddress, 'Token is not USDC');

        LibSwapper.approveMax(token, s.tokenMessenger, amount);

        ICCTPTokenMassenger(s.tokenMessenger).depositForBurn(
            amount,
            request.destinationDomainId,
            request.recipient,
            token
        );

        emit CCTPBridgeDepositAndBurnDone(
            request.destinationDomainId,
            request.recipient,
            token,
            amount
        );
    }

    /// @notice Replace a BurnMessage to change the mint recipient (to unstuck funds, only by admin)
    /// @param originalMessage Original message bytes (to replace).
    /// @param originalAttestation Original attestation bytes.
    /// @param newMintRecipient The new mint recipient, which may be the same as the original mint recipient, or different.
    function replaceDeposit(
        bytes calldata originalMessage,
        bytes calldata originalAttestation,
        bytes32 newMintRecipient
    ) external nonReentrant {
        LibDiamond.enforceIsContractOwner();

        CCTPStorage storage s = getCCTPStorage();
        ICCTPTokenMassenger(s.tokenMessenger).replaceDepositForBurn(
            originalMessage,
            originalAttestation,
            "", // newDestinationCaller, empty as we don't want to filter who the caller is on destination
            newMintRecipient
        );
    }

    function updateCCTPTokenMessengerInternal(address _address) private {
        require(_address != address(0), "Invalid TokenMessenger Address");
        CCTPStorage storage s = getCCTPStorage();
        address oldAddress = s.tokenMessenger;
        s.tokenMessenger = _address;
        emit CCTPTokenMessengerAddressUpdated(oldAddress, _address);
    }

    function updateCCTPUSDCTokenAddressInternal(address _address) private {
        require(_address != address(0), "Invalid USDC Address");
        CCTPStorage storage s = getCCTPStorage();
        address oldAddress = s.USDCTokenAddress;
        s.USDCTokenAddress = _address;
        emit CCTPUSDCTokenAddressUpdated(oldAddress, _address);
    }

    /// @dev fetch local storage
    function getCCTPStorage() private pure returns (CCTPStorage storage s) {
        bytes32 namespace = CCTP_NAMESPACE;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            s.slot := namespace
        }
    }
}