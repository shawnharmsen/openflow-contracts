// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {ISettlement} from "./interfaces/ISettlement.sol";
import {IERC20} from "./interfaces/IERC20.sol";

contract OrderExecutor {
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

    function executeOrder(ISettlement.Order calldata order) public {
        settlement.executeOrder(order);
        IERC20 toToken = IERC20(order.payload.toToken);
        toToken.transfer(msg.sender, toToken.balanceOf(address(this)));
    }

    function hook(bytes memory orderData) external {
        require(msg.sender == address(settlement));
        Data memory executorData = abi.decode(orderData, (Data));
        executorData.fromToken.approve(
            executorData.target,
            executorData.fromAmount
        );
        executorData.target.call(executorData.payload);
        executorData.toToken.transfer(
            executorData.recipient,
            executorData.toAmount
        );
    }
}
