// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;
import "forge-std/Test.sol";
import {IERC20} from "../../src/interfaces/IERC20.sol";
import {Settlement, ExecutionProxy} from "../../src/Settlement.sol";
import {ISettlement} from "../../src/interfaces/ISettlement.sol";
import {Strategy} from "../support/Strategy.sol";
import {MasterChef} from "../support/MasterChef.sol";
import {Oracle} from "../support/Oracle.sol";
import {Driver} from "../../src/Driver.sol";
import {OrderExecutor} from "../../src/executors/OrderExecutor.sol";
import {UniswapV2Aggregator} from "../../src/solvers/UniswapV2Aggregator.sol";
import {YearnVaultInteractions, IVaultRegistry, IVault} from "../support/YearnVaultInteractions.sol";
import {OpenflowFactory} from "../../src/OpenflowSdk.sol";

contract Storage is Test {
    Strategy public strategy;
    Oracle public oracle;
    IERC20 public rewardToken;
    MasterChef public masterChef;
    IVaultRegistry public vaultRegistry =
        IVaultRegistry(0x50c1a2eA0a861A967D9d0FFE2AE4012c2E053804);
    address public usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    Settlement public settlement;
    ExecutionProxy public executionProxy;
    OrderExecutor public executor;
    UniswapV2Aggregator public uniswapAggregator;
    Driver public driver;
    address public vaultInteractions;
    uint256 internal constant _USER_A_PRIVATE_KEY = 0xB0B;
    uint256 internal constant _USER_B_PRIVATE_KEY = 0xA11CE;
    address public immutable userA = vm.addr(_USER_A_PRIVATE_KEY);
    address public immutable userB = vm.addr(_USER_B_PRIVATE_KEY);

    constructor() {
        masterChef = new MasterChef();
        oracle = new Oracle();
        driver = new Driver();
        settlement = new Settlement(address(driver), address(oracle));
        executionProxy = ExecutionProxy(settlement.executionProxy());
        driver.initialize(address(settlement));
        address[] memory signers = new address[](2);
        signers[0] = userA;
        signers[1] = userB;
        driver.setSigners(signers, true);
        driver.setSignatureThreshold(2);
        vaultInteractions = address(
            new YearnVaultInteractions(address(settlement))
        );
        OpenflowFactory openflowFactory = new OpenflowFactory(
            address(settlement)
        );
        strategy = new Strategy(
            dai,
            usdc,
            address(masterChef),
            address(openflowFactory)
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
        deal(address(rewardToken), address(masterChef), 100e6);
    }

    function _sign(
        uint256 privateKey,
        bytes32 digest
    ) internal pure returns (bytes memory signature) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        signature = abi.encodePacked(r, s, v);
    }

    function _ethSign(
        uint256 privateKey,
        bytes32 digest,
        uint8 vOffset
    ) internal pure returns (bytes memory signature) {
        bytes32 ethSignDigest = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", digest)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, ethSignDigest);
        v += vOffset;
        signature = abi.encodePacked(r, s, v);
    }
}
