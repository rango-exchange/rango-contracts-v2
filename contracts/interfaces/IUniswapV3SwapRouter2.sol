// SPDX-License-Identifier: GPL-3.0-only

pragma solidity 0.8.25;
/// @dev based on IswapRouter of UniswapV3 https://docs.uniswap.org/protocol/reference/periphery/interfaces/ISwapRouter
interface IUniswapV3SwapRouter2 {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to
    ) external payable returns (uint256 amountOut);
}
