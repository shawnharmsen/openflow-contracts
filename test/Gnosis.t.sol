// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;
import {ISafe} from "../test/interfaces/IGnosisSafe.sol";
import {GnosisHelper} from "../test/support/GnosisHelper.sol";

contract GnosisTest is GnosisHelper {
    ISafe safe;

    function setUp() public {
        startHoax(userA);
        address[] memory owners = new address[](2);
        owners[0] = userA;
        owners[1] = userB;
        safe = ISafe(newSafe(owners));
    }

    function testGnosis() external {
        uint256 signatureThreshold = safe.getThreshold();
        require(signatureThreshold == 2, "Incorrect threshold");
        require(
            safe.getOwners().length == signatureThreshold,
            "Incorrect owner count"
        );
    }
}
