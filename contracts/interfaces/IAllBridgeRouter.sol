// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.16;

interface IAllBridgeRouter {

    enum MessengerProtocol {
        None,
        Allbridge,
        Wormhole,
        LayerZero
    }

    function swapAndBridge(
        bytes32 tokenAddress,
        uint256 amount,
        bytes32 recipient,
        uint8 destinationChainId,
        bytes32 receiveTokenAddress,
        uint256 nonce,
        MessengerProtocol messenger) external payable;


    // mapping(bytes32 => Pool) public pools;
    function pools(bytes32 b) external returns (address);
}