// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

interface ICCTPTokenMinter {
    /**
     * @notice Get the local token associated with the given remote domain and token.
     * @param remoteDomain Remote domain
     * @param remoteToken Remote token
     * @return local token address
     */
    function getLocalToken(uint32 remoteDomain, bytes32 remoteToken) external view returns (address);
}
