// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;
import "forge-std/Script.sol";
import "forge-std/StdJson.sol";
import {IERC20} from "../../src/interfaces/IERC20.sol";
import {Settlement, ExecutionProxy} from "../../src/Settlement.sol";
import {ISettlement} from "../../src/interfaces/ISettlement.sol";
import {Strategy} from "../../test/support/Strategy.sol";
import {MasterChef} from "../../test/support/MasterChef.sol";
import {Oracle} from "../../test/support/Oracle.sol";
import {Driver} from "../../src/Driver.sol";
import {OpenflowSdk} from "../../src/sdk/OpenflowSdk.sol";
import {OrderExecutor} from "../../src/executors/OrderExecutor.sol";
import {UniswapV2Aggregator} from "../../src/solvers/UniswapV2Aggregator.sol";
import {YearnVaultInteractions, IVaultRegistry, IVault} from "../../test/support/YearnVaultInteractions.sol";
import {OpenflowFactory} from "../../src/sdk/OpenflowFactory.sol";

contract Deploy is Script {
    Driver public driver;
    Settlement public settlement;
    ExecutionProxy public executionProxy;
    UniswapV2Aggregator public uniswapAggregator;
    OpenflowFactory public openflowFactory;
    OpenflowSdk public sdkTemplate;
    YearnVaultInteractions public vaultInteractions;
    OrderExecutor public orderExecutor;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        driver = new Driver();
        settlement = new Settlement(address(driver), address(0));
        executionProxy = ExecutionProxy(settlement.executionProxy());
        uniswapAggregator = new UniswapV2Aggregator();
        openflowFactory = new OpenflowFactory(address(settlement));
        sdkTemplate = new OpenflowSdk();
        vaultInteractions = new YearnVaultInteractions(address(settlement));
        orderExecutor = new OrderExecutor(address(settlement));
    }
}
