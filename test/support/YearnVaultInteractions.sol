// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;
import {IERC20} from "../../src/interfaces/IERC20.sol";
import {ISettlement} from "../../src/interfaces/ISettlement.sol";

interface IVaultRegistry {
    function latestVault(address token) external view returns (address vault);
}

interface IVault {
    function deposit(uint256 amount, address recipient) external;

    function withdraw(uint256 amount, address recipient) external;

    function token() external view returns (address token);

    function balanceOf(address user) external view returns (uint256 amount);

    function approve(address spender, uint256 amount) external;

    function pricePerShare() external view returns (uint256 pricePerShare);

    function transferFrom(
        address owner,
        address recipient,
        uint256 amount
    ) external;
}

contract YearnVaultInteractions {
    IVaultRegistry registry =
        IVaultRegistry(0x727fe1759430df13655ddb0731dE0D0FDE929b04);
    address public settlement;
    address public executionProxy;

    constructor(address _settlement) {
        settlement = _settlement;
        executionProxy = ISettlement(settlement).executionProxy();
    }

    function deposit(address token, address recipient) external {
        IVault vault = IVault(registry.latestVault(token));
        require(address(vault) != address(0), "Invalid vault");
        uint256 balance = IERC20(token).balanceOf(address(this));
        IERC20(token).approve(address(vault), type(uint256).max);
        vault.deposit(balance, recipient);
    }

    function withdraw(address yvToken) external {
        require(msg.sender == executionProxy, "Only execution proxy");
        address signatory;
        assembly {
            signatory := shr(96, calldataload(sub(calldatasize(), 20)))
        }
        IVault vault = IVault(yvToken);
        uint256 amount = vault.balanceOf(signatory);
        vault.transferFrom(signatory, address(this), amount);
        vault.withdraw(type(uint256).max, address(settlement));
    }
}
