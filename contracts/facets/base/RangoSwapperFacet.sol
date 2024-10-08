// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import "../../libraries/LibDiamond.sol";
import "../../libraries/LibSwapper.sol";
import "../../utils/ReentrancyGuard.sol";
import "../../libraries/LibPausable.sol";

contract RangoSwapperFacet is ReentrancyGuard{
    /// Events ///

    /// @notice initializes the base swapper and sets the init params
    /// @param _weth Address of wrapped token (WETH, WBNB, etc.) on the current chain
    function initBaseSwapper(address _weth, address payable _feeReceiver) public {
        LibDiamond.enforceIsContractOwner();
        LibSwapper.setWeth(_weth);    
        LibSwapper.updateFeeContractAddress(_feeReceiver);           
    }

    /// @notice Sets the wallet that receives Rango's fees from now on
    /// @param _address The receiver wallet address
    function updateFeeReceiver(address payable _address) external {
        LibDiamond.enforceIsContractOwner();
        LibSwapper.updateFeeContractAddress(_address);
    }

    /// @notice Transfers an ERC20 token from this contract to msg.sender
    /// @dev This endpoint is to return money to a user if we didn't handle failure correctly and the money is still in the contract
    /// @dev Currently the money goes to admin and they should manually transfer it to a wallet later
    /// @param _tokenAddress The address of ERC20 token to be transferred
    /// @param _amount The amount of money that should be transfered
    function refund(address _tokenAddress, uint256 _amount) external {
        LibDiamond.enforceIsContractOwner();
        LibPausable.enforceNotPaused();
        IERC20 ercToken = IERC20(_tokenAddress);
        uint balance = ercToken.balanceOf(address(this));
        require(balance >= _amount, "Insufficient balance");

        SafeERC20.safeTransfer(ercToken, msg.sender, _amount);

        emit LibSwapper.Refunded(_tokenAddress, _amount);
    }

    /// @notice Transfers the native token from this contract to msg.sender
    /// @dev This endpoint is to return money to a user if we didn't handle failure correctly and the money is still in the contract
    /// @dev Currently the money goes to admin and they should manually transfer it to a wallet later
    /// @param _amount The amount of native token that should be transfered
    function refundNative(uint256 _amount) external {
        LibDiamond.enforceIsContractOwner();
        LibPausable.enforceNotPaused();
        uint balance = address(this).balance;
        require(balance >= _amount, "Insufficient balance");

        LibSwapper._sendToken(LibSwapper.ETH, _amount, msg.sender, false);

        emit LibSwapper.Refunded(LibSwapper.ETH, _amount);
    }

    /// @notice Does a simple on-chain swap
    /// @param request The general swap request containing from/to token and fee/affiliate rewards
    /// @param calls The list of DEX calls
    /// @param receiver The address that should receive the output of swaps.
    /// @return The byte array result of all DEX calls
    function onChainSwaps(
        LibSwapper.SwapRequest memory request,
        LibSwapper.Call[] calldata calls,
        address receiver
    ) external payable nonReentrant returns (bytes[] memory) {
        LibPausable.enforceNotPaused();
        require(receiver != LibSwapper.ETH, "receiver cannot be address(0)");
        (bytes[] memory result, uint outputAmount) = LibSwapper.onChainSwapsInternal(request, calls, 0);
        LibSwapper.emitSwapEvent(request, outputAmount, receiver);
        LibSwapper._sendToken(request.toToken, outputAmount, receiver, false);
        return result;
    }

    function isContractWhitelisted(address _contractAddress) external view returns (bool) {
        LibDiamond.enforceIsContractOwner();
        LibSwapper.BaseSwapperStorage storage baseSwapperStorage = LibSwapper.getBaseSwapperStorage();

        return baseSwapperStorage.whitelistContracts[_contractAddress];
    } 
}