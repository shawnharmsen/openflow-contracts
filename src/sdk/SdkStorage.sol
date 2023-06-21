// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;
import {ISettlement} from "../interfaces/ISettlement.sol";
import "../interfaces/IOpenflow.sol";

contract SdkStorage {
    IOpenflowSdk.Options public options;
    address internal _settlement;
    address internal _executionProxy;

    function _initialize(
        address settlement,
        address _manager,
        address _sender,
        address _recipient
    ) internal {
        require(_settlement == address(0), "Already initialized");
        _settlement = settlement;
        _executionProxy = ISettlement(settlement).executionProxy();
        options.driver = ISettlement(settlement).defaultDriver();
        options.oracle = ISettlement(settlement).defaultOracle();
        options.slippageBips = 150;
        options.manager = _manager;
        options.sender = _sender;
        options.recipient = _recipient;
    }

    function setOptions(
        IOpenflowSdk.Options memory _options
    ) public onlyManager {
        options = _options;
    }

    modifier onlyManager() {
        require(
            msg.sender == options.manager,
            "Only the swap manager can call this function."
        );
        _;
    }

    modifier auth() {
        require(
            msg.sender == options.sender ||
                (options.managerCanSwap && msg.sender == options.manager),
            "Only the swap manager or sender can call this function."
        );
        _;
    }
}
