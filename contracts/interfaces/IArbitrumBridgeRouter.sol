// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.16;

/// @title The interface for interacting with arbitrum bridge router
/// @author AMA
interface IArbitrumBridgeRouter {
    function getGateway(address _token) external view returns (address gateway);

    function outboundTransfer(
        address _token,
        address _to,
        uint256 _amount,
        uint256 _maxGas,
        uint256 _gasPriceBid,
        bytes calldata _data
    ) external payable returns (bytes memory);
}