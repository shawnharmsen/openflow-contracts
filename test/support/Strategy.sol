// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;
import {IERC20} from "../../src/interfaces/IERC20.sol";
import {Settlement} from "../../src/Settlement.sol";
import {MultisigOrderManager} from "../../src/MultisigOrderManager.sol";
import {SimpleChainlinkOracle} from "./SimpleChainlinkOracle.sol";
import {OpenFlowSwapper} from "./OpenFlowSwapper.sol";
import {MasterChef} from "./MasterChef.sol";
import "forge-std/Test.sol";

contract Strategy is OpenFlowSwapper {
    MasterChef public masterChef;
    address public asset; // Underlying want token is DAI
    address public reward; // Reward is USDC
    MultisigOrderManager public multisigOrderManager;

    constructor(
        address _asset,
        address _reward,
        MasterChef _masterChef,
        MultisigOrderManager _multisigOrderManager,
        SimpleChainlinkOracle _oracle,
        Settlement _settlement
    ) OpenFlowSwapper(_multisigOrderManager, _oracle, _reward, _asset) {
        asset = _asset;
        reward = _reward;
        masterChef = _masterChef;
        multisigOrderManager = _multisigOrderManager;
        masterChef.accrueReward();

        // TODO: SafeApprove??
        IERC20(reward).approve(address(_settlement), type(uint256).max);
    }

    function estimatedEarnings() external view returns (uint256) {
        return masterChef.rewardOwedByAccount(address(this));
    }

    function harvest() external {
        masterChef.getReward();
        _swap();
    }

    function updateAccounting() public {}
}
