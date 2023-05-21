// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";

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
