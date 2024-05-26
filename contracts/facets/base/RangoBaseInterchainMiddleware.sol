// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import "../../libraries/LibDiamond.sol";
import "../../libraries/LibInterchain.sol";
import "../../interfaces/IRangoMiddlewareWhitelists.sol";

// @title The base contract to be used as a parent of middleware classes
// @author George
// @dev Note that this is not a facet and should be extended and deployed separately.
contract RangoBaseInterchainMiddleware {
    /// @dev keccak256("exchange.rango.middleware.base")
    bytes32 internal constant BASE_MIDDLEWARE_CONTRACT_NAMESPACE = hex"ad914d4300c64e1902ca499875cd8a76ae717047bcfaa9e806ff7ea4f6911268";

    struct BaseInterchainMiddlewareStorage {
        address owner;
    }

    /// Events
    /// @notice Emits when the owner is updated
    /// @param previousOwner The previous owner
    /// @param newOwner The new owner
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    /// @notice Notifies that admin manually refunded some money
    /// @param _token The address of refunded token, 0x000..00 address for native token
    /// @param _amount The amount that is refunded
    event Refunded(address _token, uint _amount);

    constructor(){updateOwnerInternal(tx.origin);}

    function initBaseMiddleware(
        address _owner,
        address _whitelistsContract
    ) public onlyOwner {
        require(_owner != address(0));
        updateOwnerInternal(_owner);
        LibInterchain.updateWhitelistsContractAddress(_whitelistsContract);
    }

    /// @notice used to limit access only to owner
    modifier onlyOwner() {
        require(msg.sender == getBaseInterchainMiddlewareStorage().owner, "should be called only by owner");
        _;
    }

    /// @notice used to limit access only to rango diamond
    modifier onlyDiamond() {
        // only used by CBridge for now
        {
            address s = LibInterchain.getLibInterchainStorage().whitelistsStorageContract;
            address rangoDiamond = IRangoMiddlewareWhitelists(s).getRangoDiamond();
            require(msg.sender == rangoDiamond, "should be called only from diamond");
        }
        _;
    }

    /// @notice Enables the contract to receive native ETH token from other contracts including WETH contract
    receive() external payable {}

    /// @notice returns owner of the contract
    /// @return owner address
    function getOwner() external view returns (address) {
        BaseInterchainMiddlewareStorage storage s = getBaseInterchainMiddlewareStorage();
        return s.owner;
    }

    /// @notice returns address of whitelists storage saved in LibInterchain
    /// @return whitelistsStorageContract address
    function getWhitelistsStorageContractAddress() external view returns (address) {
        return LibInterchain.getLibInterchainStorage().whitelistsStorageContract;
    }

    /// Administration & Control
    /// @notice Updates the address of owner
    /// @param newAddress The new address of owner
    function updateOwner(address newAddress) external onlyOwner {
        updateOwnerInternal(newAddress);
    }

    /// @notice updates the address of whitelists storage contract address
    /// @param newAddress the new address for whitelists storage
    function updateWhitelistsContractAddress(address newAddress) external onlyOwner {
        LibInterchain.updateWhitelistsContractAddress(newAddress);
    }

    /// @notice Transfers an ERC20 token from this contract to msg.sender
    /// @dev This endpoint is to return money to a user if we didn't handle failure correctly and the money is still in the contract
    /// @dev Currently the money goes to admin and they should manually transfer it to a wallet later
    /// @param _tokenAddress The address of ERC20 token to be transferred
    /// @param _amount The amount of money that should be transfered
    function refund(address _tokenAddress, uint256 _amount) external onlyOwner {
        IERC20 ercToken = IERC20(_tokenAddress);
        uint balance = ercToken.balanceOf(address(this));
        require(balance >= _amount, 'Insufficient balance');

        SafeERC20.safeTransfer(IERC20(_tokenAddress), msg.sender, _amount);
        emit Refunded(_tokenAddress, _amount);
    }

    /// @notice Transfers the native token from this contract to msg.sender
    /// @dev This endpoint is to return money to a user if we didn't handle failure correctly and the money is still in the contract
    /// @dev Currently the money goes to admin and they should manually transfer it to a wallet later
    /// @param _amount The amount of native token that should be transferred
    function refundNative(uint256 _amount) external onlyOwner {
        uint balance = address(this).balance;
        require(balance >= _amount, 'Insufficient balance');

        (bool sent,) = msg.sender.call{value : _amount}("");
        require(sent, "failed to send native");

        emit Refunded(LibSwapper.ETH, _amount);
    }

    /// Internal and Private functions
    function updateOwnerInternal(address newAddress) private {
        BaseInterchainMiddlewareStorage storage s = getBaseInterchainMiddlewareStorage();
        address oldAddress = s.owner;
        s.owner = newAddress;
        emit OwnershipTransferred(oldAddress, newAddress);
    }

    /// @dev fetch local storage
    function getBaseInterchainMiddlewareStorage() private pure returns (BaseInterchainMiddlewareStorage storage s) {
        bytes32 namespace = BASE_MIDDLEWARE_CONTRACT_NAMESPACE;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            s.slot := namespace
        }
    }
}