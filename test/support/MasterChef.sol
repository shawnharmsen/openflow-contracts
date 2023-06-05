// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;
import {IERC20} from "../../src/interfaces/IERC20.sol";

contract MasterChef {
    mapping(address => uint256) public rewardOwedByAccount;
    IERC20 public rewardToken =
        IERC20(0x04068DA6C83AFCFA0e13ba15A6696662335D5B75); // USDC

    // Allow anyone to accrue reward for testing purposes
    function accrueReward() external {
        rewardOwedByAccount[msg.sender] += 1e6;
    }

    // Mock reward earning. In reality user will probably call deposit or withdraw with amount set to zero to initialize a reward earn
    function getReward() external {
        uint256 amountOwed = rewardOwedByAccount[msg.sender];
        if (amountOwed > 0) {
            rewardToken.transfer(msg.sender, amountOwed);
        }
        rewardOwedByAccount[msg.sender] = 0;
    }
}
