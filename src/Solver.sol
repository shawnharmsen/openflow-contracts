// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";

contract Solver {
    // Solver data
    struct SolverData {
        ERC20 tokenA;
        ERC20 tokenB;
        uint256 swapAmount;
    }

    // Example solver does one thing: swaps token A for token B and sends to recipient
    function hook(bytes memory data) external {
        SolverData memory solverData = abi.decode(data, (SolverData));
        uint256 balanceA = solverData.tokenA.balanceOf(address(this));
        require(balanceA > 0, "No Token A balance");
        solverData.tokenB.approve(msg.sender, solverData.swapAmount);
    }
}
