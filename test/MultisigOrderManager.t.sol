// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;
import "forge-std/Test.sol";
import "./support/Storage.sol";

contract MultisigOrderManagerTest is Storage {
    address[] public signers;
    MultisigOrderManager public orderManager;

    constructor() {
        orderManager = new MultisigOrderManager();
    }

    function testInvalidateOrder() external {}

    function testInvalidateAllOrders() external {}

    function testSetSigners() external {
        signers = new address[](2);
        signers[0] = userA;
        signers[1] = userB;

        startHoax(userB);
        vm.expectRevert("Only owner");
        orderManager.setSigners(signers, false);

        vm.expectRevert("Only owner");
        orderManager.setSignatureThreshold(1);

        changePrank(orderManager.owner());
        orderManager.setSigners(signers, true);
        orderManager.setSignatureThreshold(2);
    }

    function testSetOwner() external {
        startHoax(userB);
        vm.expectRevert("Only owner");
        orderManager.setOwner(address(this));

        changePrank(orderManager.owner());
        orderManager.setOwner(address(this));
        require(orderManager.owner() == address(this), "Invalid owner");
    }
}
