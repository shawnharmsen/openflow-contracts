// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {Settlement} from "../src/Settlement.sol";
import {ISettlement} from "../src/interfaces/ISettlement.sol";
import {Strategy, MasterChef} from "./support/Strategy.sol";
import {SimpleChainlinkOracle} from "./support/SimpleChainlinkOracle.sol";
import {MultisigAuction} from "../src/MultisigAuction.sol";
import {OrderBookNotifier} from "../src/OrderBookNotifier.sol";
import {OrderExecutor} from "../src/executors/OrderExecutor.sol";
import {UniswapV2Aggregator} from "../src/solvers/UniswapV2Aggregator.sol";

contract StrategyTest is Test {
    Strategy public strategy;
    SimpleChainlinkOracle public oracle;
    IERC20 public rewardToken;
    MasterChef public masterChef;
    address public usdc = 0x04068DA6C83AFCFA0e13ba15A6696662335D5B75;
    address public dai = 0x8D11eC38a3EB5E956B052f67Da8Bdc9bef8Abf3E;
    address public weth = 0x74b23882a30290451A17c44f4F05243b6b58C76d;
    Settlement public settlement;
    OrderExecutor public executor;
    UniswapV2Aggregator public uniswapAggregator;
    OrderBookNotifier public orderBookNotifier;
    MultisigAuction public multisigAuction;
    uint256 internal constant _USER_A_PRIVATE_KEY = 0xB0B;
    uint256 internal constant _USER_B_PRIVATE_KEY = 0xA11CE;
    address public immutable userA = vm.addr(_USER_A_PRIVATE_KEY);
    address public immutable userB = vm.addr(_USER_B_PRIVATE_KEY);

    function setUp() public {
        masterChef = new MasterChef();
        oracle = new SimpleChainlinkOracle();
        settlement = new Settlement();
        orderBookNotifier = new OrderBookNotifier();
        multisigAuction = new MultisigAuction(
            address(orderBookNotifier),
            address(settlement)
        );
        strategy = new Strategy(dai, usdc, masterChef, multisigAuction, oracle);
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
        deal(address(rewardToken), address(masterChef), 100e6);
    }

    function testHarvestAndDump() external {
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
        uint256 toAmount = (quote.quoteAmount * 95) / 100;

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

        MultisigAuction multisigAuction = MultisigAuction(
            strategy.multisigAuction()
        );

        // Build digest
        bytes32 digest = settlement.buildDigest(decodedPayload);

        // Sign and execute order
        bytes memory signature1 = _sign(_USER_A_PRIVATE_KEY, digest);
        bytes memory signature2 = _sign(_USER_B_PRIVATE_KEY, digest);
        bytes memory signatures = abi.encodePacked(signature1, signature2);

        // Build order
        // See "Contract Signature" section of https://docs.safe.global/learn/safe-core/safe-core-protocol/signatures
        bytes32 s = bytes32(uint256(96)); // offset - 96
        bytes32 v = bytes32(uint256(0)); // type
        bytes memory encodedSignatures = abi.encodePacked(
            abi.encode(multisigAuction, s, v, signatures.length),
            signatures
        );
        ISettlement.Order memory order = ISettlement.Order({
            signature: encodedSignatures,
            data: executorData,
            payload: decodedPayload
        });

        address[] memory signers = new address[](2);
        signers[0] = userA;
        signers[1] = userB;
        multisigAuction.addSigners(signers);

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
