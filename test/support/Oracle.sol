// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;
import {IERC20} from "../../src/interfaces/IERC20.sol";

interface IChainklinkAggregator {
    function latestAnswer() external view returns (uint256);
}

/// @title Sample Chainlink Oracle
/// @dev Not to be used in production
contract Oracle {
    address public usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public usdcOracle = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6; // Chainlink decimals is 8 --in practice need to account for decimals difference
    address public daiOracle = 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9; // Chainlink decimals is 8 --in practice need to account for decimals difference
    mapping(address => address) public chainlinkOracleByToken;

    constructor() {
        chainlinkOracleByToken[usdc] = usdcOracle;
        chainlinkOracleByToken[dai] = daiOracle;
    }

    function getChainlinkPrice(
        address token
    ) internal view returns (uint256 price) {
        price = IChainklinkAggregator(chainlinkOracleByToken[token])
            .latestAnswer();
    }

    function calculateEquivalentAmountAfterSlippage(
        address _fromToken,
        address _toToken,
        uint256 _amountIn,
        uint256 _slippageBips
    ) external view returns (uint256 amountOut) {
        if (!(_fromToken == usdc || _fromToken == dai)) {
            revert("Oracle: Unsupported token");
        }
        uint256 fromTokenPrice = getChainlinkPrice(_fromToken);
        uint256 toTokenPrice = getChainlinkPrice(_toToken);
        uint256 fromTokenDecimals = IERC20(_fromToken).decimals();
        uint256 toTokenDecimals = IERC20(_toToken).decimals();
        uint256 priceRatio = (10 ** toTokenDecimals * fromTokenPrice) /
            toTokenPrice;
        uint256 decimalsAdjustment;
        if (fromTokenDecimals >= toTokenDecimals) {
            decimalsAdjustment = fromTokenDecimals - toTokenDecimals;
        } else {
            decimalsAdjustment = toTokenDecimals - fromTokenDecimals;
        }
        if (decimalsAdjustment > 0) {
            amountOut =
                (_amountIn * priceRatio * (10 ** decimalsAdjustment)) /
                10 ** (decimalsAdjustment + fromTokenDecimals);
        } else {
            amountOut = (_amountIn * priceRatio) / 10 ** toTokenDecimals;
        }
        amountOut = ((10000 - _slippageBips) * amountOut) / 10000;
    }
}
