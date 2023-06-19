// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;
import {IERC20} from "../../src/interfaces/IERC20.sol";
import "../../src/interfaces/IOpenflow.sol";

contract SdkIntegrationExample {
    IOpenflowSdk public openflowSdk;

    constructor(address _openflowFactory) {
        address sdkInstanceManager = msg.sender;
        openflowSdk = IOpenflowFactory(_openflowFactory).newSdkInstance(
            sdkInstanceManager
        );
    }

    function swap(address fromToken, address toToken) external {
        IERC20(fromToken).approve(address(openflowSdk), type(uint256).max);
        openflowSdk.swap(fromToken, toToken);
    }
}
