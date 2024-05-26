// SPDX-License-Identifier: GPL-3.0-only

pragma solidity 0.8.25;

/// @dev based on Curve router contract https://github.com/curvefi/curve-router-ng/blob/master/contracts/Router.vy

interface ICurve {
    function exchange(
        address [11] calldata _route,
        uint256 [5][5] calldata _swap_params,
        uint256 _amount,
        uint256 _expected,
        address [5] calldata _pools,
        address _receiver
    ) external payable returns (uint256 amountOut);
}
