// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;
import {ISafe, ISafeFactory} from "../interfaces/IGnosisSafe.sol";
import "../support/Storage.sol";

contract GnosisHelper is Storage {
    address public constant safeFactory =
        0xa6B71E26C5e0845f74c812102Ca7114b6a896AB2;
    address public constant implementation =
        0xd9Db270c1B5E3Bd161E8c8503c55cEABeE709552;
    bytes internal constant _initializerPart1 =
        hex"b63e800d0000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000140000000000000000000000000f48f2b2d2a534e402487b3ee7c18c33aec0fe5e40000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000";
    bytes internal constant _initializerPart2 =
        hex"0000000000000000000000000000000000000000000000000000000000000000";
    uint256 internal _nonce;

    function newSafe(
        address[] memory owners
    ) public returns (address safeAddress) {
        bytes memory initializer = abi.encodePacked(
            _initializerPart1,
            owners[0],
            _initializerPart2
        );
        safeAddress = ISafeFactory(safeFactory).createProxyWithNonce(
            implementation,
            initializer,
            _nonce++
        );
        for (uint256 ownerIdx = 1; ownerIdx < owners.length; ownerIdx++) {
            address owner = owners[ownerIdx];
            ISafe safe = ISafe(safeAddress);
            uint256 currentThreshold = safe.getThreshold();
            addOwnerWithThreshold(safe, owner, currentThreshold + 1);
        }
    }

    function generateSimpleSignatureBytes(
        address account
    ) public pure returns (bytes memory signatures) {
        bytes memory signatureStart = hex"000000000000000000000000";
        bytes
            memory signatureEnd = hex"000000000000000000000000000000000000000000000000000000000000000001";
        signatures = abi.encodePacked(signatureStart, account, signatureEnd);
    }

    function addOwnerWithThreshold(
        ISafe safe,
        address owner,
        uint256 threshold
    ) public {
        address owner0 = safe.getOwners()[0];
        bytes memory signatures = generateSimpleSignatureBytes(owner0);
        bytes memory data = abi.encodeWithSelector(
            ISafe.addOwnerWithThreshold.selector,
            owner,
            threshold
        );

        safe.execTransaction(
            address(safe),
            0,
            data,
            ISafe.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            signatures
        );
    }
}
