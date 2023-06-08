// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

interface IOpenFlowSwapper {
    function setOracle(address oracle) external;

    function setSlippage(uint256 slippage) external;

    function setMaxAuctionDuration(uint256 duration) external;
}
