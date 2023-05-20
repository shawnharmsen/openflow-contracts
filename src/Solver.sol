// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {ISettlement} from "./interfaces/ISettlement.sol";

contract Solver {
    ISettlement public settlement;
    address owner;

    struct SolverData {
        ERC20 fromToken;
        ERC20 toToken;
        uint256 fromAmount;
        uint256 toAmount;
        address recipient;
        address target;
        bytes data;
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

        // Allow target to spend input token
        solverData.fromToken.approve(solverData.target, solverData.fromAmount);

        // Perform swap
        solverData.target.call(solverData.data);

        // Allow settlement to spend token B
        solverData.toToken.transfer(solverData.recipient, solverData.toAmount);
    }
}
