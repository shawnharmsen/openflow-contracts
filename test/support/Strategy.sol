// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;
import {IERC20} from "../../src/interfaces/IERC20.sol";
import {IMasterChef} from "../../src/interfaces/IMasterChef.sol";
import {OpenFlowSwapper} from "./OpenFlowSwapper.sol";

contract Strategy is OpenFlowSwapper {
    address public masterChef;
    address public asset; // Underlying want token is DAI
    address public reward; // Reward is USDC
    address public manager;

    constructor(
        address _asset,
        address _reward,
        address _masterChef,
        address _driver,
        address _settlement
    ) OpenFlowSwapper(_driver, _settlement, _reward, _asset) {
        asset = _asset;
        reward = _reward;
        masterChef = _masterChef;
        manager = msg.sender;

        IERC20(reward).approve(address(_settlement), type(uint256).max);
    }

    function estimatedEarnings() external view returns (uint256) {
        return IMasterChef(masterChef).rewardOwedByAccount(address(this));
    }

    function harvest() external {
        IMasterChef(masterChef).getReward();
        _swap();
    }

    function updateAccounting() public {}

    function sweep(address token) external {
        require(msg.sender == manager);
        IERC20(token).transfer(manager, IERC20(token).balanceOf(address(this)));
    }
}
