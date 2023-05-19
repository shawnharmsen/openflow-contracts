// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {ISettlement} from "./interfaces/ISettlement.sol";

contract Solver {
    ISettlement public settlement;
    address owner;

    struct SolverData {
        ERC20 tokenA;
        ERC20 tokenB;
        uint256 swapAmount;
    }

    constructor(address _settlement) {
        settlement = ISettlement(_settlement);
        owner = msg.sender;
    }

    function executeOrder(ISettlement.Order calldata order) public {
        require(owner == msg.sender);
        settlement.executeOrder(order);
    }

    // Example solver does one thing: swaps token A for token B and then allows settlement to spend the swapped tokens
    function hook(bytes memory data) external {
        require(msg.sender == address(settlement));

        // Decode data
        SolverData memory solverData = abi.decode(data, (SolverData));

        // Allow settlement to spend token B
        solverData.tokenB.approve(address(settlement), solverData.swapAmount);
    }
}
