// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

interface IRango2 {
    /**
     * @dev feeType: 
     * 0: platform fee
     * 1: affiliate fee
     * 2: destination executor fee
     */
    struct AffiliatorFee {
        address payable affiliatorAddress;
        uint256 amount;
        uint8 feeType;
    }

    struct RangoBridgeRequest {
        address requestId;
        address token;
        uint256 amount;
        AffiliatorFee[] affiliateFees;
        uint256 totalAffiliateFee;
        uint16 dAppTag;
        string dAppName;
    }

    enum BridgeType {
        Across,
        CBridge,
        Hop,
        Hyphen,
        Multichain,
        Stargate,
        Synapse,
        Thorchain,
        Symbiosis,
        Axelar,
        Voyager,
        Poly,
        OptimismBridge,
        ArbitrumBridge,
        Wormhole,
        AllBridge,
        CCTP,
        Connext,
        NitroAssetForwarder,
        DeBridge,
        YBridge,
        Swft,
        Orbiter,
        ChainFlip
    }

    /// @notice Status of cross-chain swap
    /// @param Succeeded The whole process is success and end-user received the desired token in the destination
    /// @param RefundInSource Bridge was out of liquidity and middle asset (ex: USDC) is returned to user on source chain
    /// @param RefundInDestination Our handler on dest chain this.executeMessageWithTransfer failed and we send middle asset (ex: USDC) to user on destination chain
    /// @param SwapFailedInDestination Everything was ok, but the final DEX on destination failed (ex: Market price change and slippage)
    enum CrossChainOperationStatus {
        Succeeded,
        RefundInSource,
        RefundInDestination,
        SwapFailedInDestination
    }

    event RangoBridgeInitiated(
        address indexed requestId,
        address bridgeToken,
        uint256 bridgeAmount,
        address receiver,
        uint256 destinationChainId,
        bool hasInterchainMessage,
        bool hasDestinationSwap,
        uint8 indexed bridgeId,
        uint16 indexed dAppTag,
        string dAppName
    );

    event RangoBridgeCompleted(
        address indexed requestId,
        address indexed token,
        address indexed originalSender,
        address receiver,
        uint256 amount,
        CrossChainOperationStatus status,
        uint16 dAppTag
    );
}
