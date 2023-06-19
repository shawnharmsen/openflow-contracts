// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;
import "./support/Storage.sol";
import {SdkIntegrationExample} from "./support/SdkIntegrationExample.sol";
import {ISettlement} from "../src/interfaces/ISettlement.sol";

contract SdkIntegrationTest is Storage {
    uint256 public constant INITIAL_TOKEN_AMOUNT = 100 * 1e6;
    IERC20 public fromToken = IERC20(usdc);
    IERC20 public toToken = IERC20(dai);
    SdkIntegrationExample public integrationExample;

    constructor() {
        integrationExample = new SdkIntegrationExample(
            address(openflowFactory)
        );
        deal(
            address(fromToken),
            address(integrationExample),
            INITIAL_TOKEN_AMOUNT
        );
    }

    function testSdk() external {
        ISettlement.Payload memory decodedPayload;
        ISettlement.Order memory order;
        bytes32 digest;
        {
            vm.recordLogs();

            integrationExample.swap(address(fromToken), address(toToken));

            Vm.Log[] memory swapLogs = vm.getRecordedLogs();
            uint256 submitIndex = swapLogs.length - 1;
            (decodedPayload, ) = abi.decode(
                swapLogs[submitIndex].data,
                (ISettlement.Payload, bytes)
            );
            /// @dev Build executor data.
            order.payload = decodedPayload;
            digest = settlement.buildDigest(decodedPayload);
        }

        /// @dev Get quote.
        uint256 fromAmount = INITIAL_TOKEN_AMOUNT;
        require(fromAmount > 0, "Invalid fromAmount");
        uint256 toAmount;
        bytes memory payload;
        {
            UniswapV2Aggregator.Quote memory quote = uniswapAggregator.quote(
                fromAmount,
                address(fromToken),
                address(toToken)
            );
            uint256 slippageBips = 20; // .2% - Skim .2% off of quote after estimated swap fees
            toAmount = (quote.quoteAmount * (10000 - slippageBips)) / 10000;
            payload = abi.encodeWithSelector(
                UniswapV2Aggregator.executeOrder.selector,
                quote.routerAddress,
                quote.path,
                fromAmount,
                toAmount
            );
        }

        /// @dev Build solver interactions.
        ISettlement.Interaction[][2] memory solverInteractions;

        /// @dev Sign order payload.
        order.signature = abi.encodePacked(decodedPayload.sender);
        order.multisigSignature = abi.encodePacked(
            _sign(_USER_A_PRIVATE_KEY, digest),
            _ethSign(_USER_B_PRIVATE_KEY, digest, 4)
        );

        /// @dev Build order data.
        OrderExecutor.Data memory data;
        data.fromToken = fromToken;
        data.toToken = toToken;
        data.fromAmount = fromAmount;
        data.toAmount = toAmount;
        data.recipient = address(integrationExample);
        data.target = address(uniswapAggregator);
        data.payload = payload;
        order.data = abi.encode(data);

        /// @dev Execute order.
        executor.executeOrder(order, solverInteractions);
    }
}
