// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

interface IOracle {
    function calculateEquivalentAmountAfterSlippage(
        address _fromToken,
        address _toToken,
        uint256 _amountIn,
        uint256 _slippageBips
    ) external view returns (uint256 amountOut);
}
