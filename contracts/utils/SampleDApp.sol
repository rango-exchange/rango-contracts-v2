// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import "../interfaces/IRangoMessageReceiver.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";


/// @title Sample dApp contract
/// @author George
/// @notice This sample contract that can send message through Rango. In destination it just receives tokens and transfers it to user. This contract is just for demonstration and is not meant to be used in production.
contract SampleDApp is IRangoMessageReceiver, ReentrancyGuard {

    /// owner address used for refunds in case you got tokens stuck in the contract
    address public owner;
    /// whitelist of which contracts can call handleRangoMessage function.
    mapping(address => bool) whitelistedCallers;

    event WhitelistedCallersAdded(address[] callers);
    event WhitelistedCallersRemoved(address[] callers);

    constructor(){owner = tx.origin;}
    receive() external payable {}
    modifier onlyOwner(){
        require(msg.sender == owner, "Can be called only by owner");
        _;
    }
    modifier onlyWhitelistCaller(){
        require(whitelistedCallers[msg.sender] == true, "Can be called only by whitelisted contract");
        _;
    }

    function addWhitelistCallers(address[] calldata callers) external onlyOwner {
        for (uint256 i = 0; i < callers.length; i++) {
            whitelistedCallers[callers[i]] = true;
        }
        emit WhitelistedCallersAdded(callers);
    }

    function removeWhitelistCallers(address[] calldata callers) external onlyOwner {
        for (uint256 i = 0; i < callers.length; i++) {
            whitelistedCallers[callers[i]] = false;
        }
        emit WhitelistedCallersRemoved(callers);
    }


    /// @notice a simple struct used as message
    struct SimpleTokenMessage {
        address token;
        address receiver;
    }

    function sendTokenWithMessageThroughRango(
        address rangoContractToCall,
        address token,
        uint amount,
        bytes calldata rangoCallData) external payable nonReentrant {

        // transfer tokens from user
        if (token == address(0)) {
            require(msg.value == amount, "Insufficient Eth");
        } else {
            SafeERC20.safeTransferFrom(IERC20(token), msg.sender, address(this), amount);
            SafeERC20.forceApprove(IERC20(token), rangoContractToCall, amount);
        }

        // call rango for swap/bridge
        (bool success,) = rangoContractToCall.call{value : msg.value}(rangoCallData);
        require(success, "Failed");

    }

    // @dev this contract is called in the destination chain
    function handleRangoMessage(
        address token,
        uint amount,
        ProcessStatus status,
        bytes memory message
    ) external onlyWhitelistCaller nonReentrant {
        SimpleTokenMessage memory m = abi.decode((message), (SimpleTokenMessage));

        /// decide upon status or contents of the message
        // if (status==ProcessStatus.SUCCESS){
        //     ... some custom logic
        // }
        //if (token!=m.token){
        //     ... some custom logic, for example emit an Event that expected token in message differs from the received token
        //}

        if (token == address(0)) {
            (bool sent,) = m.receiver.call{value : amount}("");
            require(sent, "failed to send native");
        } else {
            SafeERC20.safeTransfer(IERC20(token), m.receiver, amount);
        }
    }

    /// @notice refund if token is stuck in the contract, only callable by owner.
    function refund(address _tokenAddress, uint256 _amount) external onlyOwner {
        if (_tokenAddress == address(0)) {
            (bool sent,) = msg.sender.call{value : _amount}("");
            require(sent, "failed to send native");
        }
        else {
            IERC20 ercToken = IERC20(_tokenAddress);
            uint balance = ercToken.balanceOf(address(this));
            require(balance >= _amount, 'Insufficient balance');
            SafeERC20.safeTransfer(IERC20(_tokenAddress), msg.sender, _amount);
        }
    }
}