// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;
import "./support/Storage.sol";

contract EthSignTest is Storage {
    uint256 public constant INITIAL_TOKEN_AMOUNT = 100 * 1e6;
    IERC20 public fromToken = IERC20(usdc);
    IERC20 public toToken = IERC20(weth);

    function testOrderExecutionEthSign() external {
        startHoax(address(userA));

        /// @dev Give user A from token.
        deal(address(fromToken), address(userA), INITIAL_TOKEN_AMOUNT);

        /// @dev User A approve settlement.
        fromToken.approve(address(settlement), type(uint256).max);

        /// @dev Get quote from sample aggregator.
        uint256 fromAmount = INITIAL_TOKEN_AMOUNT;
        require(fromAmount > 0, "Invalid fromAmount");
        UniswapV2Aggregator.Quote memory quote = uniswapAggregator.quote(
            fromAmount,
            address(fromToken),
            address(toToken)
        );
        uint256 slippageBips = 20;
        uint256 toAmount = (quote.quoteAmount * (10000 - slippageBips)) / 10000;

        /// @dev Build payload.
        ISettlement.Hooks memory hooks; // Optional pre and post swap hooks.
        ISettlement.Payload memory payload = ISettlement.Payload({
            fromToken: address(fromToken),
            toToken: address(toToken),
            fromAmount: fromAmount,
            toAmount: toAmount,
            sender: address(userA),
            recipient: address(userA),
            deadline: uint32(block.timestamp),
            scheme: ISettlement.Scheme.EthSign,
            hooks: hooks
        });

        bytes memory signature;
        {
            /// @dev Build digest. Order digest is what will be signed.
            bytes32 digest = settlement.buildDigest(payload);

            /// @dev Sign and execute order.
            bytes32 ethSignDigest = keccak256(
                abi.encodePacked("\x19Ethereum Signed Message:\n32", digest)
            );
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(
                _USER_A_PRIVATE_KEY,
                ethSignDigest
            );
            signature = abi.encodePacked(r, s, v);
        }

        /// @notice Execute order
        bytes memory executorData = abi.encode(
            OrderExecutor.Data({
                fromToken: fromToken,
                toToken: toToken,
                fromAmount: fromAmount,
                toAmount: toAmount,
                recipient: address(userA),
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
        ISettlement.Order memory order = ISettlement.Order({
            signature: signature,
            data: executorData,
            payload: payload
        });
        ISettlement.Interaction[][2] memory solverInteractions;
        executor.executeOrder(order, solverInteractions);
    }
}
