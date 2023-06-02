// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {ISettlement} from "../../src/interfaces/ISettlement.sol";
import {IERC20} from "../../src/interfaces/IERC20.sol";
import {Strategy} from "./Strategy.sol";

interface IStrategyProfitEscrow {
    function approveSwap(
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

    function executeOrder(
        Strategy strategy,
        uint256 fromAmount,
        uint256 toAmount,
        bytes calldata data
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
        ISettlement.Payload memory payload = strategyProfitEscrow.approveSwap(
            fromAmount,
            toAmount
        );

        // Build order
        ISettlement.Order memory order = ISettlement.Order({
            signature: abi.encodePacked(strategyProfitEscrow),
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
