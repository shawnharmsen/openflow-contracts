// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;
import {IERC20} from "../../src/interfaces/IERC20.sol";
import "../../src/interfaces/IOpenflow.sol";

contract SdkIntegrationExample {
    IOpenflowSdk public sdk;

    constructor(address _openflowFactory) {
        address sdkInstanceManager = msg.sender;
        sdk = IOpenflowFactory(_openflowFactory).newSdkInstance(
            sdkInstanceManager
        );
    }

    function swap(address fromToken, address toToken) external {
        IERC20(fromToken).approve(address(sdk), type(uint256).max);
        sdk.swap(fromToken, toToken);
    }

    function updateOptions() external {
        IOpenflowSdk.Options memory options = sdk.options();
        options.auctionDuration = 60 * 5; // Set auction duration to 5 Minutes.
        options.slippageBips = 40; // Update slippage bips to 40.
        sdk.setOptions(options);
    }
}
