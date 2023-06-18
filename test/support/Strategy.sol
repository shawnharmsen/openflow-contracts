// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;
import {IERC20} from "../../src/interfaces/IERC20.sol";
import {IMasterChef} from "../../src/interfaces/IMasterChef.sol";
import {OpenflowSdk} from "../../src/OpenflowSdk.sol";

contract Strategy is OpenflowSdk {
    address public masterChef;
    address public asset; // Underlying want token is DAI
    address public reward; // Reward is USDC

    constructor(
        address _asset,
        address _reward,
        address _masterChef,
        address _settlement
    ) OpenflowSdk(_settlement) {
        asset = _asset;
        reward = _reward;
        masterChef = _masterChef;
        IERC20(reward).approve(address(_settlement), type(uint256).max);
    }

    function estimatedEarnings() external view returns (uint256) {
        return IMasterChef(masterChef).rewardOwedByAccount(address(this));
    }

    function harvest() external {
        IMasterChef(masterChef).getReward();
        _swap(reward, asset);
    }
}
