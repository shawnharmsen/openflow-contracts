// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;
import {IERC20} from "../../src/interfaces/IERC20.sol";
import {IMasterChef} from "../../src/interfaces/IMasterChef.sol";
import "forge-std/Test.sol";
import "../../src/interfaces/IOpenflow.sol";

contract Strategy {
    address public owner;
    address public masterChef;
    address public asset; // Underlying want token is DAI
    address public reward; // Reward is USDC
    bool public automaticSwapsPaused;
    IOpenflowSdk public openflowSdk;

    constructor(
        address _asset,
        address _reward,
        address _masterChef,
        address _openflowFactory
    ) {
        owner = msg.sender;
        asset = _asset;
        reward = _reward;
        masterChef = _masterChef;

        openflowSdk = IOpenflowFactory(_openflowFactory).newSdkInstance(
            msg.sender
        );

        IERC20(reward).approve(address(openflowSdk), type(uint256).max);
    }

    function estimatedEarnings() external view returns (uint256) {
        return IMasterChef(masterChef).rewardOwedByAccount(address(this));
    }

    function setAutomaticSwapPaused(bool status) external {
        require(msg.sender == owner, "Only owner");
        automaticSwapsPaused = status;
    }

    function harvest() external {
        IMasterChef(masterChef).getReward();
        openflowSdk.swap(reward, asset);
    }
}
