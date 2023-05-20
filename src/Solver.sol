// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {ISettlement} from "./interfaces/ISettlement.sol";

contract Swapper {
    function swap(
        address tokenA,
        address tokenB,
        uint256 amountIn,
        uint256 amountOut
    ) external {
        ERC20(tokenA).transferFrom(msg.sender, address(this), amountIn);
        ERC20(tokenB).transfer(msg.sender, amountOut);
    }
}

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

    function hook(bytes memory data) external {
        require(msg.sender == address(settlement));
        Data memory data = abi.decode(data, (Data));
        data.fromToken.approve(data.target, data.fromAmount);
        data.target.call(data.payload);
        data.toToken.transfer(data.recipient, data.toAmount);
    }
}
