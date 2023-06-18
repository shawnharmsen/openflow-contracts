// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {ISettlement} from "./ISettlement.sol";

interface IOrderManager {
    function digestApproved(
        address signatory,
        bytes32 digest
    ) external view returns (bool approved);

    function submitOrder(
        ISettlement.Payload memory payload
    ) external returns (bytes memory orderUid);

    function invalidateOrder(bytes memory orderUid) external;

    function invalidateAllOrders() external;
}

contract DcaLogic {
    bytes[] orderUids;
    uint256 orderUidsLength;
    mapping(uint256 => bytes) orderUidByIdx;

    function swapWithSteps(
        address fromToken,
        address toToken,
        uint256 targetPrice,
        uint256 abortPrice,
        uint256 steps
    ) external {}

    function checkDcaOrder() external {}
}
