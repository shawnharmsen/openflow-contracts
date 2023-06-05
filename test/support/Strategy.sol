// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;
import {IERC20} from "../../src/interfaces/IERC20.sol";
import {ISettlement} from "../../src/interfaces/ISettlement.sol";
import {MultisigAuction, IMultisigAuction} from "../../src/MultisigAuction.sol";
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
    MultisigAuction public multisigAuction;

    constructor(
        address _orderBook,
        MasterChef _masterChef,
        address _settlement
    ) {
        masterChef = _masterChef;
        masterChef.accrueReward();
        reward = masterChef.rewardToken();
        multisigAuction = new MultisigAuction(_orderBook, _settlement);
        // TODO: SafeApprove??
        reward.approve(address(multisigAuction), type(uint256).max);
    }

    function estimatedEarnings() external view returns (uint256) {
        return masterChef.rewardOwedByAccount(address(this));
    }

    function harvest() external {
        masterChef.getReward();

        // Create posthook
        ISettlement.Interaction[][2] memory contractInteractions;
        contractInteractions[1] = new ISettlement.Interaction[](1);
        contractInteractions[1][0] = ISettlement.Interaction({
            target: address(this),
            value: 0,
            callData: abi.encodeWithSelector(this.updateAccounting.selector)
        });
        uint256 amountIn = reward.balanceOf(address(this));
        uint256 minAmountOut = 100;
        multisigAuction.initiateSwap(
            IMultisigAuction.SwapOrder({
                fromToken: address(reward),
                toToken: address(asset),
                amountIn: amountIn,
                minAmountOut: minAmountOut,
                recipient: address(this),
                interactions: contractInteractions
            })
        );
    }

    function updateAccounting() public {}
}
