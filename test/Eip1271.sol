// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {Settlement} from "../src/Settlement.sol";
import {ISettlement} from "../src/interfaces/ISettlement.sol";
import {Strategy} from "./support/Strategy.sol";
import {MasterChef} from "./support/MasterChef.sol";
import {Oracle} from "./support/Oracle.sol";
import {IOpenFlowSwapper} from "../src/interfaces/IOpenFlowSwapper.sol";
import {MultisigOrderManager} from "../src/MultisigOrderManager.sol";
import {OrderExecutor} from "../src/executors/OrderExecutor.sol";
import {UniswapV2Aggregator} from "../src/solvers/UniswapV2Aggregator.sol";

contract Eip1271Test is Test {
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
    uint256 internal constant _USER_A_PRIVATE_KEY = 0xB0B;
    uint256 internal constant _USER_B_PRIVATE_KEY = 0xA11CE;
    address public immutable userA = vm.addr(_USER_A_PRIVATE_KEY);
    address public immutable userB = vm.addr(_USER_B_PRIVATE_KEY);

    function setUp() public {
        masterChef = new MasterChef();
        oracle = new Oracle();
        multisigOrderManager = new MultisigOrderManager();
        settlement = new Settlement(address(multisigOrderManager));
        multisigOrderManager.initialize(address(settlement));
        address[] memory signers = new address[](2);
        signers[0] = userA;
        signers[1] = userB;
        multisigOrderManager.setSigners(signers, true);
        multisigOrderManager.setSignatureThreshold(2);
        uint32 auctionDuration = 60 * 5; // 5 minutes for example
        uint256 slippageBips = 100; // 1% - Large slippage for test reliability
        strategy = new Strategy(
            dai,
            usdc,
            address(masterChef),
            address(multisigOrderManager),
            address(settlement)
        );
        console.log(strategy.manager());
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
        deal(address(rewardToken), address(masterChef), 100e6);
    }

    function testOrderExecutionEip1271() external {
        // Get quote
        IERC20 fromToken = IERC20(strategy.reward());
        IERC20 toToken = IERC20(strategy.asset());
        uint256 fromAmount = strategy.estimatedEarnings();
        require(fromAmount > 0, "Invalid fromAmount");
        UniswapV2Aggregator.Quote memory quote = uniswapAggregator.quote(
            fromAmount,
            address(fromToken),
            address(toToken)
        );
        uint256 slippageBips = 20; // .2% - Skim .2% off of quote after estimated swap fees
        uint256 toAmount = (quote.quoteAmount * (10000 - slippageBips)) / 10000;

        vm.recordLogs();
        strategy.harvest();
        Vm.Log[] memory harvestLogs = vm.getRecordedLogs();

        uint256 submitIndex = harvestLogs.length - 1;
        ISettlement.Payload memory decodedPayload = abi.decode(
            harvestLogs[submitIndex].data,
            (ISettlement.Payload)
        );

        // Build executor data
        bytes memory executorData = abi.encode(
            OrderExecutor.Data({
                fromToken: fromToken,
                toToken: toToken,
                fromAmount: fromAmount,
                toAmount: toAmount,
                recipient: address(strategy),
                target: address(uniswapAggregator),
                payload: abi.encodeWithSelector(
                    UniswapV2Aggregator.executeOrder.selector,
                    quote.routerAddress,
                    quote.path,
                    fromAmount,
                    toAmount
                )
            })
        );

        // Build digest
        bytes32 digest = settlement.buildDigest(decodedPayload);

        // Sign and execute order
        bytes memory signature1 = _sign(_USER_A_PRIVATE_KEY, digest);
        bytes memory signature2 = _sign(_USER_B_PRIVATE_KEY, digest);
        bytes memory signatures = abi.encodePacked(signature1, signature2);

        // Build order
        // See "Contract Signature" section of https://docs.safe.global/learn/safe-core/safe-core-protocol/signatures
        // {32-bytes signature verifier}{32-bytes data position}{1-byte signature type}{32-bytes length}{n-bytes data}
        // TODO: Test with multiple contract signatures
        bytes32 s = bytes32(uint256(0x60));
        bytes1 v = bytes1(uint8(0)); // type zero - contract sig
        bytes memory encodedSignatures = abi.encodePacked(
            abi.encode(strategy, s, v),
            signatures.length,
            signatures
        );
        ISettlement.Order memory order = ISettlement.Order({
            signature: encodedSignatures,
            data: executorData,
            payload: decodedPayload
        });

        // Build after swap hook
        ISettlement.Interaction[][2] memory solverInteractions;

        // Execute order
        executor.executeOrder(order, solverInteractions);
    }

    function _sign(
        uint256 privateKey,
        bytes32 digest
    ) internal pure returns (bytes memory signature) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        signature = abi.encodePacked(r, s, v);
    }
}
