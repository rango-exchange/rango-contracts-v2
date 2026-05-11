// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

/// @title Reentrancy Guard
/// @notice Abstract contract to provide protection against reentrancy.
/// @dev Uses EIP-1153 transient storage (TSTORE/TLOAD). The status slot is
/// automatically cleared at the end of the transaction by the EVM, so a typical
/// guarded call pays ~100 gas for entry + ~100 gas for exit instead of the
/// ~2,200 gas of a cold SSTORE + warm SSTORE reset. Requires the cancun EVM.
abstract contract ReentrancyGuard {
    /// @dev Transient storage slot for the reentrancy status flag.
    /// Keeps the same namespace string as the previous SSTORE-based layout so
    /// the slot identity is stable across the upgrade, even though transient
    /// storage occupies a separate address space from regular storage.
    bytes32 private constant NAMESPACE = keccak256("exchange.rango.reentrancyguard");

    error ReentrancyError();

    uint256 private constant _ENTERED = 1;

    modifier nonReentrant() {
        bytes32 slot = NAMESPACE;
        uint256 status;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            status := tload(slot)
        }
        if (status == _ENTERED) revert ReentrancyError();
        // solhint-disable-next-line no-inline-assembly
        assembly {
            tstore(slot, _ENTERED)
        }
        _;
        // Reset so subsequent guarded calls in the same tx (e.g. via multicall)
        // can re-enter. Transient storage auto-clears at tx end, but not between
        // sibling calls within a tx.
        // solhint-disable-next-line no-inline-assembly
        assembly {
            tstore(slot, 0)
        }
    }
}
