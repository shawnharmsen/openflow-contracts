// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;
import {IERC20} from "../../src/interfaces/IERC20.sol";

interface IVaultRegistry {
    function latestVault(address token) external view returns (address vault);
}

interface IVault {
    function deposit(uint256 amount, address recipient) external;
}

contract YearnVaultDepositor {
    IVaultRegistry registry =
        IVaultRegistry(0x727fe1759430df13655ddb0731dE0D0FDE929b04);

    function deposit(address token, address recipient) external {
        IVault vault = IVault(registry.latestVault(token));
        require(address(vault) != address(0), "Invalid vault");
        uint256 balance = IERC20(token).balanceOf(address(this));
        IERC20(token).approve(address(vault), type(uint256).max);
        vault.deposit(balance, recipient);
    }
}
