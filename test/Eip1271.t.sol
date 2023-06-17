// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;
import "./support/Storage.sol";

contract Eip1271Test is Storage {
    event Log(bytes byt);

    function testOrderExecutionEip1271() external {
        // Get quote
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
        ISettlement.Payload memory decodedPayload = abi.decode(
            harvestLogs[submitIndex].data,
            (ISettlement.Payload)
        );

        // Build executor data
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

        // Build digest
        bytes32 digest = settlement.buildDigest(decodedPayload);

        // Sign and execute order
        bytes memory signature1 = _sign(_USER_A_PRIVATE_KEY, digest);
        bytes memory signature2 = _sign(_USER_B_PRIVATE_KEY, digest);
        bytes memory signatures = abi.encodePacked(signature1, signature2);

        // Build order
        // See "Contract Signature" section of https://docs.safe.global/learn/safe-core/safe-core-protocol/signatures
        // {32-bytes signature verifier}{32-bytes data position}{1-byte signature type}{32-bytes length}{n-bytes data}
        // TODO: Test with multiple contract signatures
        // bytes32 s = bytes32(uint256(0x60));
        // bytes1 v = bytes1(uint8(0)); // type zero - contract sig
        // bytes memory encodedSignatures = abi.encodePacked(
        //     abi.encode(strategy, s, v),
        //     signatures.length,
        //     signatures
        // );

        bytes memory encodedSignatures = abi.encodePacked(strategy, signatures);
        emit Log(encodedSignatures);
        ISettlement.Order memory order = ISettlement.Order({
            signature: encodedSignatures,
            data: executorData,
            payload: decodedPayload
        });

        // Build after swap hook
        ISettlement.Interaction[][2] memory solverInteractions;

        // Execute order
        executor.executeOrder(order, solverInteractions);
    }
}
