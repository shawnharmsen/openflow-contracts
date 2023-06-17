// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {Settlement} from "../../src/Settlement.sol";
import {OrderExecutor} from "../../src/executors/OrderExecutor.sol";
import {ISettlement} from "../../src/interfaces/ISettlement.sol";
import {IERC20} from "../../src/interfaces/IERC20.sol";
import {UniswapV2Aggregator} from "../../src/solvers/UniswapV2Aggregator.sol";

contract DexAggregatorTest is Test {
    UniswapV2Aggregator public uniswapAggregator;
    address public usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    uint256 public amountIn = 1e6;

    constructor() {
        uniswapAggregator = new UniswapV2Aggregator();
    }

    function testPriceQuote() external {
        UniswapV2Aggregator.Dex memory dex = UniswapV2Aggregator.Dex({
            name: "Sushiswap",
            factoryAddress: 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac,
            routerAddress: 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F
        });

        uniswapAggregator.addDex(dex);

        vm.expectRevert("Dex exists");
        uniswapAggregator.addDex(dex);

        UniswapV2Aggregator.Quote memory quote = uniswapAggregator.quote(
            amountIn,
            usdc,
            weth
        );
        require(quote.quoteAmount > 0, "Invalid to amount");
    }

    function testSetOwner() external {
        uniswapAggregator.setOwner(address(this));
    }

    function testOrderFill() external {}
}
