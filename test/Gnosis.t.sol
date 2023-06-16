// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;
import {ISafe} from "../test/interfaces/IGnosisSafe.sol";
import {GnosisHelper} from "../test/support/GnosisHelper.sol";

contract GnosisTest is GnosisHelper {
    ISafe safe;
    bytes4 private constant _EIP1271_MAGICVALUE = 0x1626ba7e;

    function setUp() public {
        startHoax(userA);
        address[] memory owners = new address[](2);
        owners[0] = userA;
        owners[1] = userB;
        safe = ISafe(newSafe(owners));
    }

    function testSafeConstruction() external {
        uint256 signatureThreshold = safe.getThreshold();
        require(signatureThreshold == 2, "Incorrect threshold");
        require(
            safe.getOwners().length == signatureThreshold,
            "Incorrect owner count"
        );
    }

    function testSafeSign() external {
        bytes
            memory orderDigest = hex"9de4c55938fc5d093859fb29a973a31dfd516c76d39063470be94ad8518874a0";

        bytes32 safeDigest = safe.getMessageHashForSafe(
            address(safe),
            orderDigest
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            _USER_A_PRIVATE_KEY,
            safeDigest
        );
        bytes memory userASignature = abi.encodePacked(r, s, v);
        (v, r, s) = vm.sign(_USER_B_PRIVATE_KEY, safeDigest);
        bytes memory userBSignature = abi.encodePacked(r, s, v);

        // Derived signatories must be in sequential order
        bytes memory signature = abi.encodePacked(
            userASignature,
            userBSignature
        );
        require(
            safe.isValidSignature(bytes32(orderDigest), signature) ==
                _EIP1271_MAGICVALUE,
            "Bad signature"
        );
    }
}
