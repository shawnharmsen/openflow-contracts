// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {ISettlement} from "./ISettlement.sol";

interface IMultisigOrderManager {
    function checkNSignatures(
        bytes32 digest,
        bytes memory signature
    ) external view;

    function digestApproved(
        address signatory,
        bytes32 digest
    ) external view returns (bool approved);

    function submitOrder(ISettlement.Payload memory payload) external;

    function signers(address) external view returns (bool);
}
