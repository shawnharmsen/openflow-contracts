// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;
import {OpenflowSdk} from "./OpenflowSdk.sol";

contract OpenflowFactory {
    address public settlement;

    constructor(address _settlement) {
        settlement = _settlement;
    }

    function newSdkInstance() external returns (OpenflowSdk sdk) {
        address _manager = msg.sender;
        return newSdkInstance(_manager);
    }

    function newSdkInstance(address _manager) public returns (OpenflowSdk sdk) {
        address _sender = msg.sender;
        address _recipient = msg.sender;
        return newSdkInstance(_manager, _sender, _recipient);
    }

    function newSdkInstance(
        address _manager,
        address _sender,
        address _recipient
    ) public returns (OpenflowSdk sdk) {
        return new OpenflowSdk(settlement, _manager, _sender, _recipient);
    }
}
