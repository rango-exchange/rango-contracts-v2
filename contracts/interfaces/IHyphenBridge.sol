// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

/// @title An interface to RangoHyphen.sol contract to improve type hinting
/// @author Hellboy
interface IHyphenBridge {

    /// @notice Executes a hyphen bridge call for native tokens
    /// @param receiver The receiver address in the destination chain
    /// @param toChainId The network id of destination chain, ex: 56 for BSC
    /// @param tag The tag string that is only used for analytics purposes in hyphen
    function depositNative(
        address receiver,
        uint256 toChainId,
        string calldata tag
    ) external payable;

    /// @notice Executes a hyphen bridge call for ERC20 (non-native) tokens
    /// @param receiver The receiver address in the destination chain
    /// @param toChainId The network id of destination chain, ex: 56 for BSC
    /// @param tokenAddress The requested token to bridge
    /// @param amount The requested amount to bridge
    /// @param tag The tag string that is only used for analytics purposes in hyphen
    function depositErc20(
        uint256 toChainId,
        address tokenAddress,
        address receiver,
        uint256 amount,
        string calldata tag
    ) external;

}