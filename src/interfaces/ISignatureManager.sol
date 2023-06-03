// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface ISignatureManager {
    function signers(address signer) external view returns (bool);
}
