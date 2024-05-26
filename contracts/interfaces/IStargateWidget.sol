// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

interface IStargateWidget {
    function partnerSwap(bytes2 _partnerId) external;
}
