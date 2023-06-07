// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {Settlement} from "../src/Settlement.sol";
import {ISettlement} from "../src/interfaces/ISettlement.sol";
import {Strategy} from "../test/support/Strategy.sol";
import {MasterChef} from "../test/support/MasterChef.sol";
import {Oracle} from "../test/support/Oracle.sol";
import {MultisigOrderManager} from "../src/MultisigOrderManager.sol";
import {OrderExecutor} from "../src/executors/OrderExecutor.sol";
import {UniswapV2Aggregator} from "../src/solvers/UniswapV2Aggregator.sol";

contract Deploy is Script {
    Strategy public strategy;
    Oracle public oracle;
    IERC20 public rewardToken;
    MasterChef public masterChef;
    address public usdc = 0x04068DA6C83AFCFA0e13ba15A6696662335D5B75;
    address public dai = 0x8D11eC38a3EB5E956B052f67Da8Bdc9bef8Abf3E;
    address public weth = 0x74b23882a30290451A17c44f4F05243b6b58C76d;
    Settlement public settlement;
    OrderExecutor public executor;
    UniswapV2Aggregator public uniswapAggregator;
    MultisigOrderManager public multisigOrderManager;
    uint256 internal constant _USER_A_PRIVATE_KEY = 0xB0B;
    uint256 internal constant _USER_B_PRIVATE_KEY = 0xA11CE;
    address public immutable userA = vm.addr(_USER_A_PRIVATE_KEY);
    address public immutable userB = vm.addr(_USER_B_PRIVATE_KEY);

    address x48_1 = 0x4800C3b3B570bE4EeE918404d0f847c1Bf25826b;
    address x48_2 = 0x481140F916a4e64559694DB4d56D692CadC0326c;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        masterChef = new MasterChef();
        oracle = new Oracle();
        settlement = new Settlement();
        multisigOrderManager = new MultisigOrderManager(address(settlement));
        address[] memory signers = new address[](2);
        signers[0] = x48_1;
        signers[1] = x48_2;
        multisigOrderManager.setSigners(signers, true);
        multisigOrderManager.setSignatureThreshold(2);
        uint256 slippageBips = 100; // 1% - Large slippage for test reliability
        strategy = new Strategy(
            dai,
            usdc,
            address(masterChef),
            address(multisigOrderManager),
            address(oracle),
            slippageBips,
            address(settlement)
        );
        masterChef.initialize(address(strategy));
        masterChef.accrueReward();
        rewardToken = IERC20(masterChef.rewardToken());
        executor = new OrderExecutor(address(settlement));
        uniswapAggregator = new UniswapV2Aggregator();
        uniswapAggregator.addDex(
            UniswapV2Aggregator.Dex({
                name: "Spookyswap",
                factoryAddress: 0x152eE697f2E276fA89E96742e9bB9aB1F2E61bE3,
                routerAddress: 0xbE4fC72f8293F9D3512d58B969c98c3F676cB957
            })
        );
    }
}
