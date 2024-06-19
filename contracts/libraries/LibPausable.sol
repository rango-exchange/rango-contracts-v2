// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

/// @title Reentrancy Guard
/// @author 0xiDen
/// @notice Abstract contract to provide protection against reentrancy
library LibPausable {
    /// Storage ///
    bytes32 private constant NAMESPACE = keccak256("exchange.rango.pausable");

    /// Types ///

    struct PausableStorage {
        bool isPaused;
    }

    /// Events ///

    /// @notice Notifies that Rango's paused state is updated
    /// @param _oldPausedState The previous paused state
    /// @param _newPausedState The new fee wallet address
    event PausedStateUpdated(bool _oldPausedState, bool _newPausedState);

    /// Errors ///

    /// Constants ///

    /// Modifiers ///

    /// Internal Methods ///

    /// @notice Sets the isPaused state for Rango
    /// @param _paused The receiver wallet address
    function updatePauseState(bool _paused) internal {
        PausableStorage storage pausableStorage = getPausableStorage();

        bool oldState = pausableStorage.isPaused;
        pausableStorage.isPaused = _paused;

        emit PausedStateUpdated(oldState, _paused);
    }

    function enforceNotPaused() internal {
        PausableStorage storage pausableStorage = getPausableStorage();
        require(pausableStorage.isPaused == false, "Paused");
    }

    /// Private Methods ///

    /// @dev fetch local storage
    function getPausableStorage() private pure returns (PausableStorage storage data) {
        bytes32 position = NAMESPACE;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            data.slot := position
        }
    }
}