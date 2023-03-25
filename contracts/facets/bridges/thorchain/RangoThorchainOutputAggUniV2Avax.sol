// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.16;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../../../interfaces/IThorchainRouter.sol";
import "../../../interfaces/IUniswapV2.sol";

/// @title Contract to handle thorchain output and pass it to a dex that implements UniV2 interface.
/// @author Thinking Particle
/// @notice Thorchain provides native token on destination chain. To swap it to desired token, this contract passes the native token to a dex.
/// @dev Thorchain only provides the desired token and the minimum amount to be received. Therefore, we cannot implement a single contract that supports all dexes. Instead we should deploy multiple instances of this contract for each dex and find the best one when creating the input transaction.
contract RangoThorchainOutputAggUniV2 is ReentrancyGuard {
    /// @dev wrapped native token contract address
    address public WETH;
    /// @dev router contract address which implements UniswapV2 router
    IUniswapV2 public dexRouter;

    /// @param _weth wrapped native token contract address
    /// @param _dexRouter router contract address which implements UniswapV2 router
    constructor(address _weth, address _dexRouter) {
        WETH = _weth;
        dexRouter = IUniswapV2(_dexRouter);
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
    /// @param amountOutMin The minimum output amount below which the swap is invalid.
    function swapOut(address token, address to, uint256 amountOutMin) public payable nonReentrant {
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = token;
        dexRouter.swapExactAVAXForTokens{value : msg.value}(amountOutMin, path, to, type(uint).max);
    }
}