// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;
import "forge-std/Script.sol";
import "forge-std/StdJson.sol";
import {Settlement, ExecutionProxy} from "../../src/Settlement.sol";
import {Oracle} from "../../test/support/Oracle.sol";
import {OpenflowProxy} from "../../src/sdk/OpenflowProxy.sol";
import {Driver} from "../../src/Driver.sol";
import {OpenflowSdk} from "../../src/sdk/OpenflowSdk.sol";
import {OrderExecutor} from "../../src/executors/OrderExecutor.sol";
import {UniswapV2Aggregator} from "../../src/solvers/UniswapV2Aggregator.sol";
import {YearnVaultInteractions} from "../../test/support/YearnVaultInteractions.sol";
import {OpenflowFactory} from "../../src/sdk/OpenflowFactory.sol";
import {SdkIntegrationExample} from "../../test/support/SdkIntegrationExample.sol";

contract Deploy is Script {
    Driver public driver;
    Settlement public settlement;
    ExecutionProxy public executionProxy;
    UniswapV2Aggregator public uniswapAggregator;
    OpenflowFactory public openflowFactory;
    OpenflowSdk public openflowSdk;
    YearnVaultInteractions public vaultInteractions;
    OrderExecutor public orderExecutor;
    OpenflowProxy public oracle;
    SdkIntegrationExample public sdkIntegrationExample;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);

        // Deploy
        driver = new Driver();
        oracle = new OpenflowProxy(address(0), deployer);
        settlement = new Settlement(address(driver), address(oracle));
        executionProxy = ExecutionProxy(settlement.executionProxy());
        uniswapAggregator = new UniswapV2Aggregator();
        openflowFactory = new OpenflowFactory(address(settlement));
        openflowSdk = new OpenflowSdk();
        openflowFactory.newSdkVersion(address(openflowSdk));
        vaultInteractions = new YearnVaultInteractions(address(settlement));
        orderExecutor = new OrderExecutor(address(settlement));
        sdkIntegrationExample = new SdkIntegrationExample(
            address(openflowFactory)
        );

        // Print
        console.log("settlement", address(settlement));
        console.log("sdkIntegrationExample", address(sdkIntegrationExample));
        console.log("openflowFactory", address(openflowFactory));
        console.log("openflowSdk", address(openflowSdk));
        console.log("orderExecutor", address(orderExecutor));
        console.log("driver", address(driver));
        console.log("executionProxy", address(executionProxy));
        console.log("oracle", address(oracle));
        console.log("vaultInteractions", address(vaultInteractions));
        console.log("uniswapAggregator", address(uniswapAggregator));
    }
}
