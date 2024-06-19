// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { LibDiamond } from "../../libraries/LibDiamond.sol";
import { IERC173 } from "../../interfaces/IERC173.sol";

contract OwnershipFacet is IERC173 {
    /// Storage ///
    bytes32 internal constant NAMESPACE = keccak256("exchange.rango.facets.ownership");
    struct Storage {
        address newOwner;
    }

    /// Errors ///

    error NoNullOwner();
    error NewOwnerMustNotBeSelf();
    error NoPendingOwnershipTransfer();
    error NotPendingOwner();

    /// Events ///

    event OwnershipTransferRequested(address indexed _from, address indexed _to);

    /// External Methods ///

    /// @notice Explicitly burn ownership, this causes no more contracts to be whitelisted and new facets cannot be added.
    function burnOwnership() external {
        LibDiamond.enforceIsContractOwner();
        LibDiamond.setContractOwner(address(0));
    }

    /// @notice Initiates transfer of ownership to a new address
    /// @param _newOwner the address to transfer ownership to
    function transferOwnership(address _newOwner) external override {
        LibDiamond.enforceIsContractOwner();
        Storage storage s = getStorage();

        if (_newOwner == address(0)) revert NoNullOwner();

        if (_newOwner == LibDiamond.contractOwner()) revert NewOwnerMustNotBeSelf();

        s.newOwner = _newOwner;
        emit OwnershipTransferRequested(msg.sender, s.newOwner);
    }

    /// @notice Cancel transfer of ownership
    function cancelOwnershipTransfer() external {
        LibDiamond.enforceIsContractOwner();
        Storage storage s = getStorage();

        if (s.newOwner == address(0)) revert NoPendingOwnershipTransfer();
        s.newOwner = address(0);
    }

    /// @notice Confirms transfer of ownership to the calling address (msg.sender)
    function confirmOwnershipTransfer() external {
        Storage storage s = getStorage();
        address _pendingOwner = s.newOwner;
        if (msg.sender != _pendingOwner) revert NotPendingOwner();
        emit OwnershipTransferred(LibDiamond.contractOwner(), _pendingOwner);
        LibDiamond.setContractOwner(_pendingOwner);
        s.newOwner = address(0);
    }

    /// @notice Return the current owner address
    /// @return owner_ The current owner address
    function owner() external view override returns (address owner_) {
        owner_ = LibDiamond.contractOwner();
    }

    /// @dev fetch local storage
    function getStorage() private pure returns (Storage storage s) {
        bytes32 namespace = NAMESPACE;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            s.slot := namespace
        }
    }
}
