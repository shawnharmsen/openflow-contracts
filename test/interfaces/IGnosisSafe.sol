// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

interface ISafeFactory {
    function createProxy(
        address _singleton,
        bytes memory initializer
    ) external returns (address proxy);
}

interface ISafe {
    enum Operation {
        Call,
        DelegateCall
    }

    function isOwner(address account) external view returns (bool status);

    function getOwners() external view returns (address[] memory owners);

    function getThreshold() external view returns (uint256 threshold);

    function addOwnerWithThreshold(address owner, uint256 _threshold) external;

    function execTransaction(
        address to,
        uint256 value,
        bytes calldata data,
        Operation operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address payable refundReceiver,
        bytes memory signatures
    ) external;
}
