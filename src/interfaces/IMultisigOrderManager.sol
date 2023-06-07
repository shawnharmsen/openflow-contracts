// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {ISettlement} from "./ISettlement.sol";

interface IMultisigOrderManager {
    function checkNSignatures(bytes32 digest, bytes memory signature) external;

    function digestApproved(bytes32 digest) external view returns (bool);

    function submitOrder(ISettlement.Payload memory payload) external;
}
