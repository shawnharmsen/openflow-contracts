// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {Settlement} from "../src/Settlement.sol";
import {ISettlement} from "../src/interfaces/ISettlement.sol";
import {Strategy, MasterChef, StrategyProfitEscrow} from "./support/Strategy.sol";
import {StrategyOrderExecutor} from "../src/executors/StrategyOrderExecutor.sol";
import {UniswapV2Aggregator} from "../src/solvers/UniswapV2Aggregator.sol";

contract StrategyTest is Test {
    Strategy strategy;
    IERC20 rewardToken;
    MasterChef masterChef;
    address public usdc = 0x04068DA6C83AFCFA0e13ba15A6696662335D5B75;
    address public weth = 0x74b23882a30290451A17c44f4F05243b6b58C76d;
    Settlement public settlement;
    StrategyOrderExecutor public executor;
    UniswapV2Aggregator public uniswapAggregator;
    uint256 internal constant _USER_A_PRIVATE_KEY = 0xB0B;
    uint256 internal constant _USER_B_PRIVATE_KEY = 0xA11CE;
    address public immutable userA = vm.addr(_USER_A_PRIVATE_KEY);
    address public immutable userB = vm.addr(_USER_B_PRIVATE_KEY);

    function setUp() public {
        settlement = new Settlement();
        masterChef = new MasterChef();
        strategy = new Strategy(masterChef, address(settlement));
        rewardToken = IERC20(masterChef.rewardToken());
        executor = new StrategyOrderExecutor(address(settlement));
        uniswapAggregator = new UniswapV2Aggregator();
        uniswapAggregator.addDex(
            UniswapV2Aggregator.Dex({
                name: "Spookyswap",
                factoryAddress: 0x152eE697f2E276fA89E96742e9bB9aB1F2E61bE3,
                routerAddress: 0xbE4fC72f8293F9D3512d58B969c98c3F676cB957
            })
        );
        deal(address(rewardToken), address(masterChef), 100e6);
    }

    function testHarvestAndDump() external {
        strategy.harvest();
        IERC20 fromToken = IERC20(strategy.reward());
        IERC20 toToken = IERC20(strategy.asset());

        // Get quote
        uint256 fromAmount = fromToken.balanceOf(
            address(strategy.profitEscrow())
        );
        UniswapV2Aggregator.Quote memory quote = uniswapAggregator.quote(
            fromAmount,
            address(fromToken),
            address(toToken)
        );
        uint256 toAmount = (quote.quoteAmount * 95) / 100;

        // Build executor data
        bytes memory executorData = abi.encode(
            StrategyOrderExecutor.Data({
                fromToken: fromToken,
                toToken: toToken,
                fromAmount: fromAmount,
                toAmount: toAmount,
                recipient: address(strategy),
                target: address(uniswapAggregator),
                payload: abi.encodeWithSelector(
                    UniswapV2Aggregator.executeOrder.selector,
                    quote.routerAddress,
                    quote.path,
                    fromAmount,
                    toAmount
                )
            })
        );

        StrategyProfitEscrow profitEscrow = StrategyProfitEscrow(
            strategy.profitEscrow()
        );
        address[] memory signers = new address[](2);
        signers[0] = userA;
        signers[1] = userB;
        profitEscrow.addSigners(signers);
        bytes32 digest = executor.buildDigest(
            fromAmount,
            toAmount,
            address(strategy),
            address(profitEscrow)
        );

        // Sign and execute order
        bytes memory signature1 = _sign(_USER_A_PRIVATE_KEY, digest);
        bytes memory signature2 = _sign(_USER_B_PRIVATE_KEY, digest);
        bytes memory signatures = abi.encodePacked(signature1, signature2);
        executor.executeOrder(
            strategy,
            fromAmount,
            toAmount,
            executorData,
            signatures
        );
    }

    function _sign(
        uint256 privateKey,
        bytes32 digest
    ) internal pure returns (bytes memory signature) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        signature = abi.encodePacked(r, s, v);
    }
}
