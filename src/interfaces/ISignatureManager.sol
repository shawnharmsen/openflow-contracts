// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface ISignatureManager {
    function signers(address signer) external view returns (bool);

    function approvedHashes(address, bytes32) external view returns (bool);
}
