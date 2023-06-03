// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IEip1271SignatureValidator {
    function isValidSignature(
        bytes32,
        bytes memory
    ) external view returns (bytes4);
}
