// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

interface IRangoMiddlewareWhitelists {

    function addWhitelist(address contractAddress) external;
    function removeWhitelist(address contractAddress) external;

    function isContractWhitelisted(address _contractAddress) external view returns (bool);
    function isMessagingContractWhitelisted(address _messagingContract) external view returns (bool);

    function updateWeth(address _weth) external;
    function getWeth() external view returns (address);
    function getRangoDiamond() external view returns (address);
}



