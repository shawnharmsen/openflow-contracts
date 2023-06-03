// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;
import {IERC20} from "../../src/interfaces/IERC20.sol";
import {ISettlement} from "../../src/interfaces/ISettlement.sol";
import {StrategyProfitEscrow} from "./Signing.sol";
import "forge-std/Test.sol";

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
    }
}

contract Strategy {
    MasterChef public masterChef;
    IERC20 public asset = IERC20(0x8D11eC38a3EB5E956B052f67Da8Bdc9bef8Abf3E); // Underlying want token is DAI
    IERC20 public reward; // Reward is USDC
    address public profitEscrow;

    constructor(MasterChef _masterChef, address _settlement) {
        masterChef = _masterChef;
        masterChef.accrueReward();
        reward = masterChef.rewardToken();
        profitEscrow = address(
            new StrategyProfitEscrow(
                address(this),
                _settlement,
                address(reward),
                address(asset)
            )
        );
    }

    function harvest() external {
        masterChef.getReward();
        reward.transfer(profitEscrow, reward.balanceOf(address(this)));
    }

    function updateAccounting() public {}
}
