// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {ISettlement} from "../../src/interfaces/ISettlement.sol";

interface IOpenflowSdk {
    struct SwapConfig {
        address driver; // Driver is responsible for authenticating quote selection
        address oracle; // Oracle is responsible for determining minimum amount out for an order
        uint256 slippageBips; // Acceptable slippage threshold denoted in BIPs
        uint256 auctionDuration; // Maximum duration for auction
        // ISettlement.Hooks hooks; // Hooks for this SDK instance
    }

    function setSwapConfig(SwapConfig memory swapConfig) external;
}
