// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.16;

/// @title An interface to Router Gateway contract
/// @author Shivam Agrawal
interface IRouterGateway {
    function iSendDefaultFee() external view returns (uint256);
}
