// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;
import "forge-std/Test.sol";

import {ISettlement} from "../../src/interfaces/ISettlement.sol";
import {IERC20} from "../../src/interfaces/IERC20.sol";
import {Strategy} from "../../test/support/Strategy.sol";

interface IStrategyProfitEscrow {
    function buildPayload(
        uint256,
        uint256
    ) external returns (ISettlement.Payload memory payload);
}

contract StrategyOrderExecutor {
    ISettlement public settlement;

    struct Data {
        IERC20 fromToken;
        IERC20 toToken;
        uint256 fromAmount;
        uint256 toAmount;
        address recipient;
        address target;
        bytes payload;
    }

    constructor(address _settlement) {
        settlement = ISettlement(_settlement);
    }

    function buildDigest(
        uint256 fromAmount,
        uint256 toAmount,
        address strategy,
        address strategyProfitEscrow
    ) external view returns (bytes32 digest) {
        digest = ISettlement(settlement).buildDigest(
            buildPayload(fromAmount, toAmount, strategy, strategyProfitEscrow)
        );
    }

    function buildPayload(
        uint256 fromAmount,
        uint256 toAmount,
        address strategy,
        address strategyProfitEscrow
    ) public view returns (ISettlement.Payload memory payload) {
        payload = ISettlement.Payload({
            signingScheme: ISettlement.SigningScheme.Eip1271,
            fromToken: address(Strategy(strategy).reward()),
            toToken: address(Strategy(strategy).asset()),
            fromAmount: fromAmount,
            toAmount: toAmount,
            sender: address(strategyProfitEscrow),
            recipient: address(strategy),
            nonce: ISettlement(settlement).nonces(address(this)),
            deadline: block.timestamp
        });
    }

    function executeOrder(
        Strategy strategy,
        uint256 fromAmount,
        uint256 toAmount,
        bytes calldata data,
        bytes calldata signatures
    ) public {
        /**
         * @notice Perform EIP-1271 signing
         * @dev Executor can only control from amount and to amount
         * @dev   (cannot control recipient or tokens)
         */
        IStrategyProfitEscrow strategyProfitEscrow = IStrategyProfitEscrow(
            strategy.profitEscrow()
        );

        // Sign and generate payload
        ISettlement.Payload memory payload = buildPayload(
            fromAmount,
            toAmount,
            address(strategy),
            address(strategyProfitEscrow)
        );

        // Build order
        ISettlement.Order memory order = ISettlement.Order({
            signature: abi.encodePacked(strategyProfitEscrow, signatures),
            data: data,
            payload: payload
        });

        // Perform the swap, sending toToken to the strategy
        settlement.executeOrder(order);

        // Call a hook on the strategy if desired
        strategy.updateAccounting();
    }

    // Generic hook for executing an order
    function hook(bytes memory orderData) external {
        require(msg.sender == address(settlement));
        Data memory executorData = abi.decode(orderData, (Data));
        executorData.fromToken.approve(executorData.target, type(uint256).max); // Max approve to save gas --this contract should not hold tokens
        executorData.target.call(executorData.payload);
        executorData.toToken.transfer(
            executorData.recipient,
            executorData.toAmount
        );
    }
}
