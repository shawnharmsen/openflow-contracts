// SPDX-License-Identifier: MIT
import "./interfaces/ISettlement.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";

pragma solidity 0.8.19;

contract OrderExecutor {
    ISettlement public settlement;

    struct Data {
        ERC20 fromToken;
        ERC20 toToken;
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
        ERC20 toToken = ERC20(order.payload.toToken);
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
