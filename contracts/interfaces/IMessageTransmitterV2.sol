// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

/// @title IMessageTransmitterV2
/// @author Sunny
/// @notice Interface for V2 message transmitters, which both relay and receive messages.
interface IMessageTransmitterV2 {
    /**
     * @notice Receives an incoming message, validating the header and passing
     * the body to application-specific handler.
     * @param message The message raw bytes
     * @param signature The message signature
     * @return success bool, true if successful
     */
    function receiveMessage(bytes calldata message, bytes calldata signature) external returns (bool success);
}
