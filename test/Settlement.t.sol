// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {Settlement} from "../src/Settlement.sol";
import {OrderExecutor} from "../src/OrderExecutor.sol";
import {Swapper} from "../test/support/Swapper.sol";
import {UniswapV2Aggregator} from "../src/solvers/UniswapV2Aggregator.sol";
import {SigUtils} from "../test/utils/SigUtils.sol";
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
    Swapper public swapper;
    OrderExecutor public executor;
    IERC20 public tokenA;
    IERC20 public tokenB;
    SigUtils public sigUtils;
    UniswapV2Aggregator public uniswapAggregator;

    function setUp() public {
        // Begin as User A
        startHoax(userA);

        // Configuration
        settlement = new Settlement();
        executor = new OrderExecutor(address(settlement));
        swapper = new Swapper();
        sigUtils = new SigUtils(
            settlement.domainSeparator(),
            settlement.TYPE_HASH()
        );
        tokenA = IERC20(usdc);
        tokenB = IERC20(weth);

        // Alice gets 100 Token A
        deal(address(tokenA), userA, INITIAL_TOKEN_AMOUNT);

        // Swapper gets 100 Token B
        deal(address(tokenB), address(swapper), INITIAL_TOKEN_AMOUNT);

        // Grant settlesment infinite allowance
        tokenA.approve(address(settlement), type(uint256).max);

        // Set up aggregator
        uniswapAggregator = new UniswapV2Aggregator(weth);
        uniswapAggregator.addDex(
            UniswapV2Aggregator.Dex({
                name: "Spookyswap",
                factoryAddress: 0x152eE697f2E276fA89E96742e9bB9aB1F2E61bE3,
                routerAddress: 0xbE4fC72f8293F9D3512d58B969c98c3F676cB957
            })
        );
    }

    function testOrderExecutionEip712() external {
        // Expectations
        uint256 userATokenABalanceBefore = tokenA.balanceOf(userA);
        uint256 userATokenBBalanceBefore = tokenB.balanceOf(userA);
        uint256 swapperTokenABalanceBefore = tokenA.balanceOf(address(swapper));
        uint256 swapperTokenBBalanceBefore = tokenB.balanceOf(address(swapper));

        require(
            swapperTokenABalanceBefore == 0,
            "Swapper should not have token A"
        );
        require(
            swapperTokenBBalanceBefore == INITIAL_TOKEN_AMOUNT,
            "Swapper should have initial amount of tokens"
        );

        require(
            userATokenABalanceBefore == INITIAL_TOKEN_AMOUNT,
            "User A should have initial amount of tokens"
        );
        require(
            userATokenBBalanceBefore == 0,
            "User B should not have token B"
        );

        // Get quote
        uint256 fromAmount = 1 * 1e6;
        UniswapV2Aggregator.Quote memory quote = uniswapAggregator.quote(
            fromAmount,
            address(tokenA),
            address(tokenB)
        );
        uint256 toAmount = (quote.quoteAmount * 95) / 100;

        // Build executor data
        bytes memory executorData = abi.encode(
            OrderExecutor.Data({
                fromToken: tokenA,
                toToken: tokenB,
                fromAmount: fromAmount,
                toAmount: toAmount,
                recipient: userA,
                target: address(uniswapAggregator),
                payload: abi.encodeWithSelector(
                    UniswapV2Aggregator.executeOrder.selector,
                    quote.routerAddress,
                    quote.path,
                    tokenA,
                    fromAmount,
                    toAmount
                )
            })
        );

        // Build order
        ISettlement.Order memory order = ISettlement.Order({
            signature: hex"",
            data: executorData,
            payload: ISettlement.Payload({
                signingScheme: ISettlement.SigningScheme.Eip712,
                fromToken: address(tokenA),
                toToken: address(tokenB),
                fromAmount: fromAmount,
                toAmount: toAmount,
                sender: userA,
                recipient: userA,
                nonce: 0,
                deadline: block.timestamp
            })
        });

        // Sign order
        bytes32 digest = sigUtils.buildDigest(order.payload);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_USER_A_PRIVATE_KEY, digest);
        order.signature = abi.encodePacked(r, s, v);

        // Change to user B
        changePrank(userB);

        // Execute order
        executor.executeOrder(order);

        // Expectations after swap
        userATokenABalanceBefore = tokenA.balanceOf(userA);
        userATokenBBalanceBefore = tokenB.balanceOf(userA);
        require(
            userATokenABalanceBefore == INITIAL_TOKEN_AMOUNT - fromAmount,
            "User A should now have less token A"
        );
        require(
            userATokenBBalanceBefore == toAmount,
            "User A should now have token B"
        );

        // Expect revert if solver submits a duplicate order
        vm.expectRevert("Nonce already used");
        executor.executeOrder(order);

        // Increase nonce and try again
        order.payload.nonce++;

        // Sign order
        digest = sigUtils.buildDigest(order.payload);
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
