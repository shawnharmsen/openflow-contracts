// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;
import {OpenflowSdk} from "./OpenflowSdk.sol";

contract OpenflowSdkFactory {
    address public settlement;

    constructor(address _settlement) {
        settlement = _settlement;
    }

    function newSdkInstance() external returns (OpenflowSdk openflowSdk) {
        return newSdkInstance(msg.sender, msg.sender, msg.sender);
    }

    function newSdkInstance(
        address _manager
    ) external returns (OpenflowSdk openflowSdk) {
        return newSdkInstance(_manager, msg.sender, msg.sender);
    }

    function newSdkInstance(
        address _manager,
        address _sender,
        address _recipient
    ) public returns (OpenflowSdk openflowSdk) {
        return new OpenflowSdk(settlement, _manager, _sender, _recipient);
    }
}
