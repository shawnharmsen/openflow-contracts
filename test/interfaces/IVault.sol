// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

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
