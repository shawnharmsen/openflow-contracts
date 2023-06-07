// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IMasterChef {
    function getReward() external;

    function rewardOwedByAccount(address) external view returns (uint256);
}
