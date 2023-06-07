// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;
import {IERC20} from "../../src/interfaces/IERC20.sol";
import {IMasterChef} from "../../src/interfaces/IMasterChef.sol";
import {OpenFlowSwapper} from "./OpenFlowSwapper.sol";

contract Strategy is OpenFlowSwapper {
    address public masterChef;
    address public asset; // Underlying want token is DAI
    address public reward; // Reward is USDC
    address public multisigOrderManager;

    constructor(
        address _asset,
        address _reward,
        address _masterChef,
        address _multisigOrderManager,
        address _oracle,
        uint256 _slippageBips,
        address _settlement
    )
        OpenFlowSwapper(
            _multisigOrderManager,
            _oracle,
            _slippageBips,
            _reward,
            _asset
        )
    {
        asset = _asset;
        reward = _reward;
        masterChef = _masterChef;
        multisigOrderManager = _multisigOrderManager;

        // TODO: SafeApprove??
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
}
