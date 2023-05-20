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

contract Solver {
    // Storage
    address public owner;
    ISettlement public settlement;

    // Types
    struct SolverData {
        ERC20 fromToken;
        ERC20 toToken;
        uint256 fromAmount;
        uint256 toAmount;
        address recipient;
        address target;
        bytes data;
    }

    enum Operation {
        Call,
        DelegateCall
    }

    // Initialization
    constructor(address _settlement) {
        settlement = ISettlement(_settlement);
        owner = msg.sender;
    }

    // Order execution
    function executeOrder(ISettlement.Order calldata order) public onlyOwner {
        require(owner == msg.sender, "Only owner");
        settlement.executeOrder(order);
    }

    // Generic hook for executing arbitrary calldata
    function hook(bytes memory data) external {
        require(msg.sender == address(settlement));

        // Decode data
        SolverData memory solverData = abi.decode(data, (SolverData));

        // Allow target to spend input token
        solverData.fromToken.approve(solverData.target, solverData.fromAmount);

        // Perform swap
        solverData.target.call(solverData.data);

        // Send token B to recipient
        solverData.toToken.transfer(solverData.recipient, solverData.toAmount);
    }

    // Allow arbitrary execution by owner
    function execute(
        address to,
        uint256 value,
        bytes calldata data,
        Operation operation
    ) external returns (bool success) {
        require(owner == msg.sender, "Only owner");
        if (operation == Operation.Call) {
            assembly {
                success := call(
                    gas(),
                    to,
                    value,
                    add(data.offset, 0x20),
                    mload(data.offset),
                    0,
                    0
                )
            }
        } else if (operation == Operation.DelegateCall) {
            assembly {
                success := delegatecall(
                    gas(),
                    to,
                    add(data.offset, 0x20),
                    mload(data.offset),
                    0,
                    0
                )
            }
        }
        assembly {
            let returnDataSize := returndatasize()
            returndatacopy(0, 0, returnDataSize)
            switch success
            case 0 {
                revert(0, returnDataSize)
            }
            default {
                return(0, returnDataSize)
            }
        }
    }
}
