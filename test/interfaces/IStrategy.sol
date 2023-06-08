// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

interface IStrategy {
    function manager() external view returns (address);
}
