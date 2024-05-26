// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import "../../interfaces/IRangoOrbiter.sol";
import "../../interfaces/IOrbiterRouterV3.sol";
import "../../interfaces/IRango.sol";
import "../../utils/ReentrancyGuard.sol";
import "../../libraries/LibSwapper.sol";
import "../../libraries/LibDiamond.sol";

/// @title The root contract that handles Rango's interaction with Orbiter bridge
/// @author Thinking Particle
/// @dev This is deployed as a facet for RangoDiamond
contract RangoOrbiterFacet is IRango, ReentrancyGuard, IRangoOrbiter {

    /// Storage ///
    
    bytes32 internal constant ORBITER_NAMESPACE = keccak256("exchange.rango.facets.orbiter");

    struct OrbiterStorage {
        /// @notice List of whitelisted orbiter contracts
        mapping(address => bool) orbiterWhitelistedRouterContracts;
    }

    /// Events ///

    /// @notice Notifies that some new router addresses are whitelisted
    /// @param _addresses The newly whitelisted addresses
    event OrbiterRoutersAdded(address[] _addresses);
    /// @notice Notifies that some router addresses are blacklisted
    /// @param _addresses The addresses that are removed
    event OrbiterRoutersRemoved(address[] _addresses);

    /// Initialization ///

    /// @notice Initialize the contract.
    /// @param _addresses The contract address of the routers on the source chain.
    function initOrbiter(address[] calldata _addresses) external {
        LibDiamond.enforceIsContractOwner();
        addOrbiterRouterContractsInternal(_addresses);
    }

    /// @notice Enables the contract to receive native ETH token from other contracts including WETH contract
    receive() external payable {}

    /// @notice Adds a list of new addresses to the whitelisted orbiter router contracts
    /// @param _addresses The list of new routers
    function addOrbiterRouterContracts(address[] calldata _addresses) public {
        LibDiamond.enforceIsContractOwner();
        addOrbiterRouterContractsInternal(_addresses);
    }

    /// @notice Removes a list of routers from the whitelisted addresses
    /// @param _addresses The list of addresses that should be deprecated
    function removeOrbiterRouterContracts(address[] calldata _addresses) external {
        LibDiamond.enforceIsContractOwner();
        OrbiterStorage storage s = getOrbiterStorage();
        for (uint i = 0; i < _addresses.length; i++) {
            delete s.orbiterWhitelistedRouterContracts[_addresses[i]];
        }
        emit OrbiterRoutersRemoved(_addresses);
    }

    /// @notice Executes a DEX (arbitrary) call + a Orbiter bridge call
    /// @param request The general swap request containing from/to token and fee/affiliate rewards
    /// @param calls The list of DEX calls, if this list is empty, it means that there is no DEX call and we are only bridging
    /// @param bridgeRequest required data for the bridging step, including the destination chain and recipient wallet address
    function orbiterSwapAndBridge(
        LibSwapper.SwapRequest memory request,
        LibSwapper.Call[] calldata calls,
        OrbiterBridgeRequest memory bridgeRequest
    ) external payable nonReentrant {
        uint out = LibSwapper.onChainSwapsPreBridge(request, calls, 0);

        doOrbiterBridge(bridgeRequest, request.toToken, out);

        // event emission
        emit RangoBridgeInitiated(
            request.requestId,
            request.toToken,
            out,
            bridgeRequest.recipient,
            0,
            false,
            false,
            uint8(BridgeType.Orbiter),
            request.dAppTag);
    }

    /// @notice starts bridging through Orbiter bridge
    /// @param request The extra fields required by the orbiter bridge
    /// @param bridgeRequest The general data for bridging
    function orbiterBridge(
        OrbiterBridgeRequest memory request,
        IRango.RangoBridgeRequest memory bridgeRequest
    ) external payable nonReentrant {
        uint amount = bridgeRequest.amount;
        address token = bridgeRequest.token;
        uint amountWithFee = amount + LibSwapper.sumFees(bridgeRequest);
        // transfer tokens if necessary
        if (token == LibSwapper.ETH) {
            require(
                msg.value >= amountWithFee, "Insufficient ETH sent for bridging and fees");
        } else {
            SafeERC20.safeTransferFrom(IERC20(token), msg.sender, address(this), amountWithFee);
        }
        LibSwapper.collectFees(bridgeRequest);
        doOrbiterBridge(request, token, amount);

        // event emission
        emit RangoBridgeInitiated(
            bridgeRequest.requestId,
            token,
            amount,
            request.recipient,
            0,
            false,
            false,
            uint8(BridgeType.Orbiter),
            bridgeRequest.dAppTag
        );
    }

    /// @notice Executes an Orbiter bridge call
    /// @param request The required fields for orbiter bridge contract
    /// @param token The token to be transferred (address(0) for native)
    /// @param amount Amount of tokens to deposit. Will be amount of tokens to receive less fees.
    function doOrbiterBridge(
        OrbiterBridgeRequest memory request,
        address token,
        uint amount
    ) internal {
        OrbiterStorage storage s = getOrbiterStorage();
        require(s.orbiterWhitelistedRouterContracts[request.routerContract], "Router not whitelisted");
        if (token != LibSwapper.ETH) {
            LibSwapper.approveMax(token, request.routerContract, amount);
            IOrbiterRouterV3(request.routerContract).transferToken(token, request.recipient, amount, request.data);
        } else {
            IOrbiterRouterV3(request.routerContract).transfer{value: amount}(request.recipient, request.data);
        }
    }

    function addOrbiterRouterContractsInternal(address[] calldata _addresses) private {
        OrbiterStorage storage s = getOrbiterStorage();
        address tmpAddr;
        for (uint i = 0; i < _addresses.length; i++) {
            tmpAddr = _addresses[i];
            require(tmpAddr != address(0), "Invalid router");
            s.orbiterWhitelistedRouterContracts[tmpAddr] = true;
        }
        emit OrbiterRoutersAdded(_addresses);
    }

    /// @dev fetch local storage
    function getOrbiterStorage() private pure returns (OrbiterStorage storage s) {
        bytes32 namespace = ORBITER_NAMESPACE;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            s.slot := namespace
        }
    }

}