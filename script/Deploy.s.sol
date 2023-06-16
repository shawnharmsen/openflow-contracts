// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {Settlement} from "../src/Settlement.sol";
import {ISettlement} from "../src/interfaces/ISettlement.sol";
import {IOpenFlowSwapper} from "../src/interfaces/IOpenFlowSwapper.sol";
import {Strategy} from "../test/support/Strategy.sol";
import {MasterChef} from "../test/support/MasterChef.sol";
import {Oracle} from "../test/support/Oracle.sol";
import {MultisigOrderManager} from "../src/MultisigOrderManager.sol";
import {OrderExecutor} from "../src/executors/OrderExecutor.sol";
import {UniswapV2Aggregator} from "../src/solvers/UniswapV2Aggregator.sol";
import {YearnVaultInteractions, IVaultRegistry, IVault} from "../test/support/YearnVaultInteractions.sol";

contract Deploy is Script {
    Strategy public strategy;
    Oracle public oracle;
    IERC20 public rewardToken;
    MasterChef public masterChef;
    address public usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    Settlement public settlement;
    OrderExecutor public executor;
    UniswapV2Aggregator public uniswapAggregator;
    MultisigOrderManager public multisigOrderManager;
    address public x48_1 = 0x4800C3b3B570bE4EeE918404d0f847c1Bf25826b;
    address public x48_2 = 0x481140F916a4e64559694DB4d56D692CadC0326c;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        masterChef = new MasterChef();
        oracle = new Oracle();
        multisigOrderManager = new MultisigOrderManager();
        settlement = new Settlement(address(multisigOrderManager));
        multisigOrderManager.initialize(address(settlement));
        address[] memory signers = new address[](2);
        signers[0] = x48_1;
        signers[1] = x48_2;
        multisigOrderManager.setSigners(signers, true);
        multisigOrderManager.setSignatureThreshold(2);
        uint32 auctionDuration = 5 * 60; // 5 minutes
        uint256 slippageBips = 100;
        strategy = new Strategy(
            dai,
            usdc,
            address(masterChef),
            address(multisigOrderManager),
            address(settlement)
        );
        IOpenFlowSwapper(address(strategy)).setOracle(address(oracle));
        IOpenFlowSwapper(address(strategy)).setSlippage(slippageBips);
        IOpenFlowSwapper(address(strategy)).setMaxAuctionDuration(
            auctionDuration
        );
        masterChef.initialize(address(strategy));
        masterChef.accrueReward();
        rewardToken = IERC20(masterChef.rewardToken());
        executor = new OrderExecutor(address(settlement));
        uniswapAggregator = new UniswapV2Aggregator();
        uniswapAggregator.addDex(
            UniswapV2Aggregator.Dex({
                name: "Sushiswap",
                factoryAddress: 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac,
                routerAddress: 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F
            })
        );
        new YearnVaultInteractions(address(settlement));
    }
}
