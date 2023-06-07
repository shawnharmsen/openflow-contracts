// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {Settlement} from "../src/Settlement.sol";
import {OrderExecutor} from "../src/executors/OrderExecutor.sol";
import {UniswapV2Aggregator} from "../src/solvers/UniswapV2Aggregator.sol";
import {ISettlement} from "../src/interfaces/ISettlement.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";

contract SettlementTest is Test {
    // Constants
    uint256 internal constant _USER_A_PRIVATE_KEY = 0xB0B;
    uint256 internal constant _USER_B_PRIVATE_KEY = 0xA11CE;
    address public immutable userA = vm.addr(_USER_A_PRIVATE_KEY);
    address public immutable userB = vm.addr(_USER_B_PRIVATE_KEY);
    uint256 public constant INITIAL_TOKEN_AMOUNT = 100 * 1e18;
    address public usdc = 0x04068DA6C83AFCFA0e13ba15A6696662335D5B75;
    address public weth = 0x74b23882a30290451A17c44f4F05243b6b58C76d;

    // Storage
    Settlement public settlement;
    OrderExecutor public executor;
    IERC20 public fromToken;
    IERC20 public toToken;
    UniswapV2Aggregator public uniswapAggregator;

    function setUp() public {
        // Begin as User A
        startHoax(userA);

        // Configuration
        settlement = new Settlement();
        executor = new OrderExecutor(address(settlement));
        fromToken = IERC20(usdc);
        toToken = IERC20(weth);

        // User A gets 100 Token A
        deal(address(fromToken), userA, INITIAL_TOKEN_AMOUNT);

        // Grant settlement infinite allowance
        fromToken.approve(address(settlement), type(uint256).max);

        // Set up aggregator
        uniswapAggregator = new UniswapV2Aggregator();
        uniswapAggregator.addDex(
            UniswapV2Aggregator.Dex({
                name: "Spookyswap",
                factoryAddress: 0x152eE697f2E276fA89E96742e9bB9aB1F2E61bE3,
                routerAddress: 0xbE4fC72f8293F9D3512d58B969c98c3F676cB957
            })
        );
    }

    function testOrderExecutionEip712() external {
        // Get quote
        uint256 fromAmount = 1 * 1e6;
        UniswapV2Aggregator.Quote memory quote = uniswapAggregator.quote(
            fromAmount,
            address(fromToken),
            address(toToken)
        );
        uint256 toAmount = (quote.quoteAmount * 95) / 100;

        // Build executor data
        bytes memory executorData = abi.encode(
            OrderExecutor.Data({
                fromToken: fromToken,
                toToken: toToken,
                fromAmount: fromAmount,
                toAmount: toAmount,
                recipient: userA,
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

        // Build order
        ISettlement.Hooks memory hooks;
        ISettlement.Order memory order = ISettlement.Order({
            signature: hex"",
            data: executorData,
            payload: ISettlement.Payload({
                fromToken: address(fromToken),
                toToken: address(toToken),
                fromAmount: fromAmount,
                toAmount: toAmount,
                sender: userA,
                recipient: userA,
                nonce: 0,
                deadline: uint32(block.timestamp),
                hooks: hooks
            })
        });

        // Sign order
        bytes32 digest = settlement.buildDigest(order.payload);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_USER_A_PRIVATE_KEY, digest);
        order.signature = abi.encodePacked(r, s, v);

        // Change to user B
        changePrank(userB);

        // Track solver balance before
        address solver = userB;
        uint256 solverBalanceBefore = toToken.balanceOf(solver);

        // Expectations before swap
        uint256 userAFromTokenBalanceBefore = fromToken.balanceOf(userA);
        require(
            userAFromTokenBalanceBefore == INITIAL_TOKEN_AMOUNT,
            "User A should have initial amount of tokens"
        );

        // Build after swap solver hook
        ISettlement.Interaction[][2] memory solverInteractions;
        solverInteractions[1] = new ISettlement.Interaction[](1);
        solverInteractions[1][0] = ISettlement.Interaction({
            target: address(executor),
            value: 0,
            callData: abi.encodeWithSelector(
                OrderExecutor.sweep.selector,
                address(toToken),
                solver
            )
        });

        // Execute order
        executor.executeOrder(order, solverInteractions);

        // Make sure solver is capable of receiving profit
        {
            uint256 solverBalanceAfter = toToken.balanceOf(solver);
            uint256 solverProfit = solverBalanceAfter - solverBalanceBefore;
            require(solverProfit > 0, "Solver had zero profit");
        }

        // Expectations after swap
        userAFromTokenBalanceBefore = fromToken.balanceOf(userA);
        uint256 userAToTokenBalanceBefore = toToken.balanceOf(userA);
        require(
            userAFromTokenBalanceBefore == INITIAL_TOKEN_AMOUNT - fromAmount,
            "User A should now have less token A"
        );
        require(
            userAToTokenBalanceBefore == toAmount,
            "User A should now have token B"
        );

        // Expect revert if solver submits a duplicate order
        vm.expectRevert("Order already filled");
        executor.executeOrder(order);

        // Increase nonce and try again
        order.payload.nonce++;

        // Sign order
        digest = settlement.buildDigest(order.payload);
        (v, r, s) = vm.sign(_USER_A_PRIVATE_KEY, digest);
        order.signature = abi.encodePacked(r, s, v);

        // Increase timestamp
        vm.warp(block.timestamp + 1);

        // Expect order to expire
        vm.expectRevert("Deadline expired");
        executor.executeOrder(order);

        // Decrease timestamp
        vm.warp(block.timestamp - 1);

        // Order should execute now
        executor.executeOrder(order);
    }
}
