// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;
import "./support/Storage.sol";

contract HooksTest is Storage {
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

    function testZapIn() external {
        /// @dev Get quote.
        uint256 fromAmount = INITIAL_TOKEN_AMOUNT;
        UniswapV2Aggregator.Quote memory quote = uniswapAggregator.quote(
            fromAmount,
            address(fromToken),
            address(toToken)
        );
        uint256 toAmount = (quote.quoteAmount * 95) / 100;

        // Build hooks
        ISettlement.Interaction[] memory preHooks;
        ISettlement.Interaction[]
            memory postHooks = new ISettlement.Interaction[](1);
        postHooks[0] = ISettlement.Interaction({
            target: vaultInteractions,
            value: 0,
            data: abi.encodeWithSignature(
                "deposit(address,address)",
                toToken,
                userA
            )
        });
        ISettlement.Hooks memory hooks = ISettlement.Hooks({
            preHooks: preHooks,
            postHooks: postHooks
        });

        // Build paylod
        ISettlement.Payload memory payload = ISettlement.Payload({
            fromToken: address(fromToken),
            toToken: address(toToken),
            fromAmount: fromAmount,
            toAmount: toAmount,
            sender: userA,
            recipient: vaultInteractions,
            validFrom: uint32(block.timestamp),
            validTo: uint32(block.timestamp),
            scheme: ISettlement.Scheme.Eip712,
            driver: address(0),
            hooks: hooks
        });

        // Sign payload
        bytes32 digest = settlement.buildDigest(payload);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_USER_A_PRIVATE_KEY, digest);

        /// @dev Build executor data.
        bytes memory executorData = abi.encode(
            OrderExecutor.Data({
                fromToken: IERC20(payload.fromToken),
                toToken: IERC20(payload.toToken),
                fromAmount: payload.fromAmount,
                toAmount: payload.toAmount,
                recipient: payload.recipient,
                target: address(uniswapAggregator),
                payload: abi.encodeWithSelector(
                    UniswapV2Aggregator.executeOrder.selector,
                    quote.routerAddress,
                    quote.path,
                    payload.fromAmount,
                    payload.toAmount
                )
            })
        );

        // Build and sign order
        ISettlement.Order memory order = ISettlement.Order({
            signature: hex"",
            multisigSignature: hex"",
            data: executorData,
            payload: payload
        });
        order.signature = abi.encodePacked(r, s, v);

        // Change to user B
        changePrank(userB);

        // Make sure user has no yvToken
        IVault vault = IVault(vaultRegistry.latestVault(address(toToken)));
        require(vault.balanceOf(userA) == 0, "Invalid vault start balance");

        // Execute zap in
        ISettlement.Interaction[][2] memory solverInteractions;
        executor.executeOrder(order, solverInteractions);

        // Make sure zap was successful
        require(vault.balanceOf(userA) > 0, "Invalid vault end balance");
    }

    function testZapOut() external {
        // Execute from user A
        changePrank(userA);

        // Swap from and to token
        IERC20 tempToken = fromToken;
        fromToken = toToken;
        toToken = tempToken;

        // Allow vault interactions to zap out (this could also be done with permit)
        IVault vault = IVault(vaultRegistry.latestVault(address(fromToken)));
        vault.approve(address(vaultInteractions), type(uint256).max);

        // Build hooks
        ISettlement.Interaction[]
            memory preHooks = new ISettlement.Interaction[](1);
        preHooks[0] = ISettlement.Interaction({
            target: vaultInteractions,
            value: 0,
            data: abi.encodeWithSignature("withdraw(address)", address(vault))
        });
        ISettlement.Interaction[]
            memory postHooks = new ISettlement.Interaction[](0);
        ISettlement.Hooks memory hooks = ISettlement.Hooks({
            preHooks: preHooks,
            postHooks: postHooks
        });

        // Give user A some vault token
        deal(address(vault), userA, 1e18); // One share

        /// @dev Get quote.
        uint256 fromAmount = (vault.balanceOf(userA) * vault.pricePerShare()) /
            1e18;
        UniswapV2Aggregator.Quote memory quote = uniswapAggregator.quote(
            fromAmount,
            address(fromToken),
            address(toToken)
        );
        uint256 toAmount = (quote.quoteAmount * 95) / 100;

        // Build paylod
        ISettlement.Payload memory payload = ISettlement.Payload({
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
        });

        /// @dev Build executor data.
        bytes memory executorData = abi.encode(
            OrderExecutor.Data({
                fromToken: IERC20(payload.fromToken),
                toToken: IERC20(payload.toToken),
                fromAmount: payload.fromAmount,
                toAmount: payload.toAmount,
                recipient: payload.recipient,
                target: address(uniswapAggregator),
                payload: abi.encodeWithSelector(
                    UniswapV2Aggregator.executeOrder.selector,
                    quote.routerAddress,
                    quote.path,
                    payload.fromAmount,
                    payload.toAmount
                )
            })
        );

        // Build order
        ISettlement.Order memory order = ISettlement.Order({
            signature: hex"",
            multisigSignature: hex"",
            data: executorData,
            payload: payload
        });

        // Sign order
        bytes32 digest = settlement.buildDigest(order.payload);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_USER_A_PRIVATE_KEY, digest);
        order.signature = abi.encodePacked(r, s, v);

        // Change to user B
        changePrank(userB);

        // Execute zap out
        ISettlement.Interaction[][2] memory solverInteractions;
        executor.executeOrder(order, solverInteractions);
    }

    function testBadHook() external {
        /// @dev Get quote.
        uint256 fromAmount = INITIAL_TOKEN_AMOUNT;
        UniswapV2Aggregator.Quote memory quote = uniswapAggregator.quote(
            fromAmount,
            address(fromToken),
            address(toToken)
        );
        uint256 toAmount = (quote.quoteAmount * 95) / 100;

        // Build invalid hooks
        ISettlement.Interaction[] memory preHooks;
        ISettlement.Interaction[]
            memory postHooks = new ISettlement.Interaction[](1);
        postHooks[0] = ISettlement.Interaction({
            target: vaultInteractions,
            value: 0,
            data: "deadbeef"
        });
        ISettlement.Hooks memory hooks = ISettlement.Hooks({
            preHooks: preHooks,
            postHooks: postHooks
        });

        // Build paylod
        ISettlement.Payload memory payload = ISettlement.Payload({
            fromToken: address(fromToken),
            toToken: address(toToken),
            fromAmount: fromAmount,
            toAmount: toAmount,
            sender: userA,
            recipient: vaultInteractions,
            validFrom: uint32(block.timestamp),
            validTo: uint32(block.timestamp),
            scheme: ISettlement.Scheme.Eip712,
            driver: address(0),
            hooks: hooks
        });

        // Sign payload
        bytes32 digest = settlement.buildDigest(payload);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_USER_A_PRIVATE_KEY, digest);

        /// @dev Build executor data.
        bytes memory executorData = abi.encode(
            OrderExecutor.Data({
                fromToken: IERC20(payload.fromToken),
                toToken: IERC20(payload.toToken),
                fromAmount: payload.fromAmount,
                toAmount: payload.toAmount,
                recipient: payload.recipient,
                target: address(uniswapAggregator),
                payload: abi.encodeWithSelector(
                    UniswapV2Aggregator.executeOrder.selector,
                    quote.routerAddress,
                    quote.path,
                    payload.fromAmount,
                    payload.toAmount
                )
            })
        );

        // Build and sign order
        ISettlement.Order memory order = ISettlement.Order({
            signature: hex"",
            multisigSignature: hex"",
            data: executorData,
            payload: payload
        });
        order.signature = abi.encodePacked(r, s, v);

        // Change to user B
        changePrank(userB);

        /// @dev Execute order.
        ISettlement.Interaction[][2] memory solverInteractions;
        vm.expectRevert("Execution proxy interaction failed");
        executor.executeOrder(order, solverInteractions);
    }
}
