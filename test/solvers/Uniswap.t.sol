// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {Settlement} from "../../src/Settlement.sol";
import {OrderExecutor} from "../../src/OrderExecutor.sol";
import {Swapper} from "../../test/support/Swapper.sol";
import {SigUtils} from "../../test/utils/SigUtils.sol";
import {ISettlement} from "../../src/interfaces/ISettlement.sol";
import {IERC20} from "../../src/interfaces/IERC20.sol";
import {UniswapV2Aggregator} from "../../src/solvers/UniswapV2Aggregator.sol";

contract UniswapTest is Test {
    UniswapV2Aggregator public uniswapAggregator;

    address public router = 0xbE4fC72f8293F9D3512d58B969c98c3F676cB957;
    address public usdc = 0x04068DA6C83AFCFA0e13ba15A6696662335D5B75;
    address public weth = 0x74b23882a30290451A17c44f4F05243b6b58C76d;
    uint256 public amountIn = 1e6;

    function setUp() public {
        // Configuration
        uniswapAggregator = new UniswapV2Aggregator();

        // Add dex
        uniswapAggregator.addDex(
            UniswapV2Aggregator.Dex({
                name: "Spookyswap",
                factoryAddress: 0x152eE697f2E276fA89E96742e9bB9aB1F2E61bE3,
                routerAddress: 0xbE4fC72f8293F9D3512d58B969c98c3F676cB957
            })
        );
    }

    function testPriceQuote() external view {
        UniswapV2Aggregator.Quote memory quote = uniswapAggregator.quote(
            amountIn,
            usdc,
            weth
        );
        console.log(quote.routerAddress);
        console.log(quote.quoteAmount);
    }

    function testOrderFill() external {}
}
