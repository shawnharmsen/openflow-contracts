// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {Settlement} from "../src/Settlement.sol";
import {ISettlement} from "../src/interfaces/ISettlement.sol";
import {Solver} from "../src/Solver.sol";
import {SigUtils} from "../test/utils/SigUtils.sol";

contract SettlementTest is Test {
    // Constants
    uint256 internal constant _USER_A_PRIVATE_KEY = 0xB0B;
    uint256 internal constant _USER_B_PRIVATE_KEY = 0xA11CE;
    address public immutable userA = vm.addr(_USER_A_PRIVATE_KEY);
    address public immutable userB = vm.addr(_USER_B_PRIVATE_KEY);
    uint256 public constant INITIAL_TOKEN_AMOUNT = 100 * 1e18;

    // Storage
    Settlement public settlement;
    Solver public solver;
    ERC20 public tokenA;
    ERC20 public tokenB;
    SigUtils public sigUtils;

    function setUp() public {
        // Configuration
        settlement = new Settlement();
        solver = new Solver(address(settlement));
        sigUtils = new SigUtils(
            settlement.domainSeparator(),
            settlement.TYPE_HASH()
        );
        tokenA = new ERC20("Token A", "TOKEN_A");
        tokenB = new ERC20("Token B", "TOKEN_B");

        // Alice gets 100 Token A
        deal(address(tokenA), userA, INITIAL_TOKEN_AMOUNT);

        // Solver gets 100 Token B
        deal(address(tokenB), address(solver), INITIAL_TOKEN_AMOUNT);

        // Begin as User A
        startHoax(userA);

        // Grant settlement infinite allowance
        tokenA.approve(address(settlement), type(uint256).max);
    }

    function testOrderExecutionEip712() external {
        // Expectations
        uint256 userATokenABalanceBefore = tokenA.balanceOf(userA);
        uint256 userATokenBBalanceBefore = tokenB.balanceOf(userA);
        uint256 solverTokenABalanceBefore = tokenA.balanceOf(address(solver));
        uint256 solverTokenBBalanceBefore = tokenB.balanceOf(address(solver));
        require(
            solverTokenABalanceBefore == 0,
            "Solver should not have token A"
        );
        require(
            solverTokenBBalanceBefore == INITIAL_TOKEN_AMOUNT,
            "Solver should have initial amount of tokens"
        );

        require(
            userATokenABalanceBefore == INITIAL_TOKEN_AMOUNT,
            "User A should have initial amount of tokens"
        );
        require(
            userATokenBBalanceBefore == 0,
            "User B should not have token B"
        );

        // Solver data (optional, up to Solver to implement)
        uint256 swapAmount = 10 * 1e18;
        bytes memory solverData = abi.encode(
            Solver.SolverData({
                tokenA: tokenA,
                tokenB: tokenB,
                swapAmount: swapAmount
            })
        );

        // Build order
        ISettlement.Order memory order = ISettlement.Order({
            signature: hex"00",
            data: solverData,
            payload: ISettlement.Payload({
                signingScheme: ISettlement.SigningScheme.Eip712,
                fromToken: address(tokenA),
                toToken: address(tokenB),
                fromAmount: swapAmount,
                toAmount: swapAmount,
                sender: userA,
                recipient: userA,
                nonce: 0,
                deadline: block.timestamp
            })
        });

        // Sign order
        bytes32 digest = sigUtils.buildDigest(order.payload);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_USER_A_PRIVATE_KEY, digest);
        bytes memory signature = abi.encodePacked(r, s, v);
        order.signature = signature;

        // Execute order
        solver.executeOrder(order);

        // Expectations after swap
        userATokenABalanceBefore = tokenA.balanceOf(userA);
        userATokenBBalanceBefore = tokenB.balanceOf(userA);
        solverTokenABalanceBefore = tokenA.balanceOf(address(solver));
        solverTokenBBalanceBefore = tokenB.balanceOf(address(solver));
        require(
            solverTokenABalanceBefore == swapAmount,
            "Solver should now have token A"
        );
        require(
            solverTokenBBalanceBefore == INITIAL_TOKEN_AMOUNT - swapAmount,
            "Solver should now have less token B"
        );

        require(
            userATokenABalanceBefore == INITIAL_TOKEN_AMOUNT - swapAmount,
            "User A should now have less token A"
        );
        require(
            userATokenBBalanceBefore == swapAmount,
            "User A should now have token B"
        );

        // Expect revert if solver submits a duplicate order
        vm.expectRevert("Nonce already used");
        solver.executeOrder(order);

        // Increase nonce and try again
        order.payload.nonce++;

        // Sign order
        digest = sigUtils.buildDigest(order.payload);
        (v, r, s) = vm.sign(_USER_A_PRIVATE_KEY, digest);
        signature = abi.encodePacked(r, s, v);
        order.signature = signature;

        // Increase timestamp
        vm.warp(block.timestamp + 1);

        // Expect order to expire
        vm.expectRevert("Deadline expired");
        solver.executeOrder(order);

        // Decrease timestamp
        vm.warp(block.timestamp - 1);

        // Order should execute now
        solver.executeOrder(order);
    }
}
