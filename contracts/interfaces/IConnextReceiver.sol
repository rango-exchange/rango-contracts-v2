// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;


interface IConnextReceiver {
    function xReceive(
        bytes32 _transferId,
        uint256 _amount,
        address _asset,
        address _originSender,
        uint32 _origin,
        bytes memory _callData
    ) external payable returns (bytes memory);
}