// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;
import {IERC20} from "../../src/interfaces/IERC20.sol";

contract MasterChef {
    mapping(address => uint256) public rewardOwedByAccount;
    IERC20 public rewardToken =
        IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48); // USDC
    address public owner;
    address public strategy;

    constructor() {
        owner = msg.sender;
    }

    function accrueReward() external {
        rewardOwedByAccount[strategy] += 1e6;
    }

    function initialize(address _strategy) external {
        require(strategy == address(0), "Already initialized");
        strategy = _strategy;
    }

    // Mock reward earning. In reality user will probably call deposit or withdraw with amount set to zero to initialize a reward earn
    function getReward() external {
        uint256 amountOwed = rewardOwedByAccount[strategy];
        rewardToken.transfer(strategy, amountOwed);
        rewardOwedByAccount[strategy] = 0;
    }

    function sweep() external {
        require(msg.sender == owner);
        rewardToken.transfer(owner, rewardToken.balanceOf(address(this)));
    }
}
