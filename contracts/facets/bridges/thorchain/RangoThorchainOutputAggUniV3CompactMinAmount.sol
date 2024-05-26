// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../../../interfaces/IThorchainRouter.sol";
import "../../../interfaces/IUniswapV3.sol";
import "../../../interfaces/IWETH.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Contract to handle thorchain output and pass it to a dex that implements UniV3 interface.
/// @author Thinking Particle
/// @notice Thorchain provides native token on destination chain. To swap it to desired token, this contract passes the native token to a dex.
/// @dev Thorchain only provides the desired token and the minimum amount to be received. Therefore, we cannot implement a single contract that supports all dexes. Instead we should deploy multiple instances of this contract for each dex and find the best one when creating the input transaction.
contract RangoThorchainOutputAggUniV3 is ReentrancyGuard {
    /// @dev wrapped native token interface
    IWETH public nativeWrappedToken;
    /// @dev router contract address which implements UniswapV3 router
    IUniswapV3 public dexRouter;
    /// @dev pool fee value of UniswapV3
    uint24 public v3PoolFee;

    /// @param _weth The contract address of wrapped native token
    /// @param _dexRouter The contract address of UniswapV3 router
    /// @param _v3PoolFee The pool fee value of UniswapV3
    constructor(address _weth, address _dexRouter, uint24 _v3PoolFee) {
        nativeWrappedToken = IWETH(_weth);
        dexRouter = IUniswapV3(_dexRouter);
        v3PoolFee = _v3PoolFee;
    }

    /// @dev This contract is only implemented to handle for swap output of thorchain. Therefore swapIn function is implemented as a revert to make sure that it won't be called as swapIn handler.
    function swapIn(
        address,
        address,
        string calldata,
        address,
        uint,
        uint,
        uint
    ) public nonReentrant {
        revert("this contract only supports swapOut");
    }

    /// @notice This function is called by thorchain nodes. It receives native token and swaps it to the desired token using the dex.
    /// @dev This function creates a simple 1 step path for uniswap v2 router. Note that this function can be called by anyone including (thorchain nodes).
    /// @param token The desired token contract address
    /// @param to The wallet address should receive the output.
    /// @param amountOutMinRaw The minimum output amount below which the swap is invalid encoded as last 2 digits are exponents of 10 to be multiplied. For example 1502 means 15 * e02 = 1500
    function swapOut(address token, address to, uint256 amountOutMinRaw) public payable nonReentrant {
        uint amountOutMin = amountOutMinRaw / 100 * (10 ** (amountOutMinRaw % 100));
        nativeWrappedToken.deposit{value : msg.value}();
        SafeERC20.safeIncreaseAllowance(IERC20(address(nativeWrappedToken)), address(dexRouter), msg.value);
        dexRouter.exactInputSingle(
            IUniswapV3.ExactInputSingleParams(
            {
            tokenIn : address(nativeWrappedToken),
            tokenOut : token,
            fee : v3PoolFee,
            recipient : to,
            deadline : type(uint).max,
            amountIn : msg.value,
            amountOutMinimum : amountOutMin,
            sqrtPriceLimitX96 : 0
            })
        );
    }

}