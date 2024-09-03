// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// for bridge only, we should set src/dst the same address
struct SwapDescription {
    address srcToken;
    address dstToken;
    address receiver;
    uint256 amount;
    uint256 minReturnAmount;
}

struct DstChainDescription {
    uint32 dstChainId;
    address dstChainToken; // IERC20
    address dstAggregatorAdaptor;
    uint256 expectedDstChainTokenAmount;
    uint32 slippage;
}

interface IYBridge {
    function swapWithReferrer(
        address aggregatorAdaptor,
        SwapDescription memory swapDesc,
        bytes memory aggregatorData,
        DstChainDescription calldata dstChainDesc,
        address referrer
    ) external payable;
}