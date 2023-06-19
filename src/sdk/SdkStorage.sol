// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;
import {ISettlement} from "../interfaces/ISettlement.sol";

contract SdkStorage {
    struct SdkOptions {
        address driver; // Driver is responsible for authenticating quote selection.
        address oracle; // Oracle is responsible for determining minimum amount out for an order.
        uint256 slippageBips; // Acceptable slippage threshold denoted in BIPs.
        uint256 auctionDuration; // Maximum duration for auction.
        address manager; // Manager is responsible for managing SDK options.
        address sender; // Funds will be transferred to settlement from this sender.
        address recipient; // Funds will be sent to recipient after swap.
    }

    SdkOptions public options;
    address public settlement;
    address public executionProxy;

    constructor(
        address _settlement,
        address _manager,
        address _sender,
        address _recipient
    ) {
        settlement = _settlement;
        executionProxy = ISettlement(_settlement).executionProxy();
        options.driver = ISettlement(_settlement).defaultDriver();
        options.oracle = ISettlement(_settlement).defaultOracle();
        options.slippageBips = 150;
        options.manager = _manager;
        options.sender = _sender;
        options.recipient = _recipient;
    }

    function setOptions(SdkOptions memory _options) public onlyManager {
        options = _options;
    }

    modifier onlyManager() {
        require(
            msg.sender == options.manager,
            "Only the swap manager can call this function."
        );
        _;
    }

    modifier onlyManagerOrSender() {
        require(
            msg.sender == options.manager || msg.sender == options.sender,
            "Only the swap manager or sender can call this function."
        );
        _;
    }
}
