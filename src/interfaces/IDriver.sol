// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

interface IDriver {
    function checkNSignatures(
        bytes32 digest,
        bytes memory signature
    ) external view;

    function signers(address) external view returns (bool);
}
