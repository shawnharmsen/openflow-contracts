// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;
import "./support/Storage.sol";

contract Eip1271Test is Storage {
    function testOrderExecutionEip1271() external {
        /// @dev Get quote.
        IERC20 fromToken = IERC20(strategy.reward());
        IERC20 toToken = IERC20(strategy.asset());
        uint256 fromAmount = strategy.estimatedEarnings();
        require(fromAmount > 0, "Invalid fromAmount");
        UniswapV2Aggregator.Quote memory quote = uniswapAggregator.quote(
            fromAmount,
            address(fromToken),
            address(toToken)
        );
        uint256 slippageBips = 20; // .2% - Skim .2% off of quote after estimated swap fees
        uint256 toAmount = (quote.quoteAmount * (10000 - slippageBips)) / 10000;

        vm.recordLogs();
        strategy.harvest();
        Vm.Log[] memory harvestLogs = vm.getRecordedLogs();
        uint256 submitIndex = harvestLogs.length - 1;
        (ISettlement.Payload memory decodedPayload, ) = abi.decode(
            harvestLogs[submitIndex].data,
            (ISettlement.Payload, bytes)
        );

        /// @dev Build executor data.
        bytes memory executorData = abi.encode(
            OrderExecutor.Data({
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

        /// @dev Build digest.
        bytes32 digest = settlement.buildDigest(decodedPayload);

        /// @dev Sign order payload.
        bytes memory signature1 = _sign(_USER_A_PRIVATE_KEY, digest);
        bytes memory signature2 = _ethSign(_USER_B_PRIVATE_KEY, digest, 4);
        bytes memory signatures = abi.encodePacked(signature1, signature2);

        /// @dev Build solver interactions.
        ISettlement.Interaction[][2] memory solverInteractions;

        /// @dev Execute order.
        ISettlement.Order memory order = ISettlement.Order({
            signature: abi.encodePacked(decodedPayload.sender),
            multisigSignature: signatures,
            data: executorData,
            payload: decodedPayload
        });
        executor.executeOrder(order, solverInteractions);
    }
}
