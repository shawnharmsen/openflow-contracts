// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;
import "forge-std/Test.sol";
import "./support/Storage.sol";

contract Eip712Test is Storage {
    // Constants
    uint256 public constant INITIAL_TOKEN_AMOUNT = 100 * 1e18;

    // Storage
    IERC20 public fromToken;
    IERC20 public toToken;

    function setUp() public {
        // Begin as User A
        startHoax(userA);
        fromToken = IERC20(usdc);
        toToken = IERC20(weth);

        // User A gets 100 Token A
        deal(address(fromToken), userA, INITIAL_TOKEN_AMOUNT);

        // Grant settlement infinite allowance
        fromToken.approve(address(settlement), type(uint256).max);
    }

    function testOrderExecutionEip712() external {
        /// @dev Get quote.
        uint256 fromAmount = 1 * 1e6;
        UniswapV2Aggregator.Quote memory quote = uniswapAggregator.quote(
            fromAmount,
            address(fromToken),
            address(toToken)
        );
        uint256 toAmount = (quote.quoteAmount * 95) / 100;

        /// @dev Build executor data.
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
            multisigSignature: hex"",
            data: executorData,
            payload: ISettlement.Payload({
                fromToken: address(fromToken),
                toToken: address(toToken),
                fromAmount: fromAmount,
                toAmount: toAmount,
                sender: userA,
                recipient: userA,
                validFrom: uint32(block.timestamp),
                validTo: uint32(block.timestamp),
                scheme: ISettlement.Scheme.Eip712,
                driver: address(0),
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

        /// @dev Test execution proxy auth.
        vm.expectRevert("Only settlement");
        ISettlement.Interaction[][2] memory solverInteractions;
        solverInteractions[1] = new ISettlement.Interaction[](1);
        executionProxy.execute(address(this), solverInteractions[0]);

        /// @dev Test invalid sender.
        order.payload.sender = address(this);
        vm.expectRevert("Invalid signer");
        executor.executeOrder(order);
        order.payload.sender = userA;

        /// @dev Test invalid timestamp.
        vm.warp(block.timestamp + 1);

        /// @dev Test expired order.
        vm.expectRevert("Deadline expired");
        executor.executeOrder(order);

        /// @dev Fix timestamp.
        vm.warp(block.timestamp - 1);
        {
            // Build invalid solver hook
            ISettlement.Interaction memory invalidInteraction = ISettlement
                .Interaction({
                    target: address(executor),
                    value: 0,
                    data: hex"deadbeef"
                });
            solverInteractions[1][0] = invalidInteraction;

            /// @dev Test bad solver hook execution.
            vm.expectRevert("Order executor interaction failed");
            executor.executeOrder(order, solverInteractions);
        }

        // Build solver hook
        ISettlement.Interaction memory interaction = ISettlement.Interaction({
            target: address(executor),
            value: 0,
            data: abi.encodeWithSelector(
                OrderExecutor.sweep.selector,
                address(toToken),
                solver
            )
        });
        solverInteractions[1][0] = interaction;

        /// @dev Make sure only settlement can call executor hook
        vm.expectRevert("Only settlement");
        executor.hook(order.data);

        /// @dev Test bad executor swap hook
        {
            vm.expectRevert("Execution hook failed");
            OrderExecutor.Data memory badData = abi.decode(
                order.data,
                (OrderExecutor.Data)
            );
            badData.payload = hex"deadbeef";
            order.data = abi.encode(badData);
            executor.executeOrder(order, solverInteractions);
        }

        /// @dev Test order execution.
        order.data = executorData;
        executor.executeOrder(order, solverInteractions);

        /// @dev Make sure solver is capable of receiving profit.
        {
            uint256 solverBalanceAfter = toToken.balanceOf(solver);
            uint256 solverProfit = solverBalanceAfter - solverBalanceBefore;
            require(solverProfit > 0, "Solver had zero profit");
        }

        /// @dev Expectations after swap.
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

        /// @dev Expect revert if solver submits a duplicate order.
        vm.expectRevert("Order already filled");
        executor.executeOrder(order);
    }
}
