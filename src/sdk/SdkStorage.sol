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

    SdkOptions public sdkOptions;
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
        sdkOptions.driver = ISettlement(_settlement).defaultDriver();
        sdkOptions.oracle = ISettlement(_settlement).defaultOracle();
        sdkOptions.slippageBips = 150;
        sdkOptions.manager = _manager;
        sdkOptions.sender = _sender;
        sdkOptions.recipient = _recipient;
    }

    function setSwapConfig(SdkOptions memory _swapConfig) public onlyManager {
        sdkOptions = _swapConfig;
    }

    modifier onlyManager() {
        require(
            msg.sender == sdkOptions.manager,
            "Only the swap manager can call this function."
        );
        _;
    }

    modifier onlyManagerOrSender() {
        require(
            msg.sender == sdkOptions.manager || msg.sender == sdkOptions.sender,
            "Only the swap manager or sender can call this function."
        );
        _;
    }
}
