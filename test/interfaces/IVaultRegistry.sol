// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

interface IVaultRegistry {
    function latestVault(address token) external view returns (address vault);
}
