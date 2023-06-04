// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {ISettlement} from "../interfaces/ISettlement.sol";
import {IERC20} from "../interfaces/IERC20.sol";

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

    struct Interaction {
        address target;
        uint256 value;
        bytes callData;
    }

    function executeOrder(ISettlement.Order calldata order) public {
        settlement.executeOrder(order);
    }

    function executeOrder(
        ISettlement.Order calldata order,
        ISettlement.Interaction[][2] memory interactions
    ) public {
        // Before swap hook
        _executeInteractions(interactions[0]);

        // Execute swap
        settlement.executeOrder(order);

        // After swap hook
        _executeInteractions(interactions[1]);
    }

    function sweep(IERC20 token, address recipient) external {
        token.transfer(recipient, token.balanceOf(address(this)));
    }

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

    // Solver hooks
    function _executeInteractions(
        ISettlement.Interaction[] memory interactions
    ) internal {
        for (uint256 i; i < interactions.length; i++) {
            ISettlement.Interaction memory interaction = interactions[i];
            (bool success, ) = interaction.target.call{
                value: interaction.value
            }(interaction.callData);
            require(success, "Interaction failed");
        }
    }
}
