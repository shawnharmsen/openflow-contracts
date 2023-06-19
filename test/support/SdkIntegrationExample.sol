// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;
import {IERC20} from "../../src/interfaces/IERC20.sol";
import "../../src/interfaces/IOpenflow.sol";

contract SdkIntegrationExample {
    /// @notice Initialize SDK instance variable.
    IOpenflowSdk public sdk;

    /// @notice Create a new SDK instance.
    constructor(address _openflowFactory) {
        address sdkInstanceManager = address(this);
        sdk = IOpenflowFactory(_openflowFactory).newSdkInstance(
            sdkInstanceManager
        );
    }

    /// @notice Execute a basic swap.
    /// @dev Note: This method has no auth. If your app needs auth make sure to add it.
    function swap(address fromToken, address toToken) external {
        IERC20(fromToken).approve(address(sdk), type(uint256).max);
        sdk.swap(fromToken, toToken);
    }

    /// @notice Update SDK options.
    /// @dev Note: This method has no auth. If your app needs auth make sure to add it.
    function updateOptions() external {
        IOpenflowSdk.Options memory options = sdk.options();
        options.auctionDuration = 60 * 5; // Set auction duration to 5 Minutes.
        options.slippageBips = 40; // Update slippage bips to 40.
        sdk.setOptions(options);
    }
}
