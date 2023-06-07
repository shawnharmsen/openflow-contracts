// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;
import "forge-std/Test.sol";
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

contract MultisigSwap is Script {
    // Hardcoded values. In the future read from broadcast deployment logs
    Strategy public strategy =
        Strategy(0xC7CE9fA323bC3a13a516c3c890e87316e4b2df52);
    Oracle public oracle = Oracle(0xcA81a85e8Bd58f24Df30c670dBF8188009eE8884);
    MasterChef public masterChef =
        MasterChef(0xedE0aDA4Ec11969c31d113b2Ad069ed3333Ccb17);
    address public usdc = 0x04068DA6C83AFCFA0e13ba15A6696662335D5B75;
    address public dai = 0x8D11eC38a3EB5E956B052f67Da8Bdc9bef8Abf3E;
    address public weth = 0x74b23882a30290451A17c44f4F05243b6b58C76d;
    Settlement public settlement =
        Settlement(0x3C7488fBDED5f5e056A6cF11BB6a0e4385dce58a);
    OrderExecutor public executor =
        OrderExecutor(0xE14C923eD1cdbbE34966AfF6A54e95DeAFC310be);
    UniswapV2Aggregator public uniswapAggregator =
        UniswapV2Aggregator(0x78101Bbcb00f9A62607cd8B31BEF8358Ed33BD11);
    MultisigOrderManager public multisigOrderManager =
        MultisigOrderManager(0xE6512671fFcd79C833127363A75545b1C7baACDA);

    address public userA;
    address public userB;
    uint256 internal immutable _USER_A_PRIVATE_KEY;
    uint256 internal immutable _USER_B_PRIVATE_KEY;

    constructor() {
        _USER_A_PRIVATE_KEY = vm.envUint("PRIVATE_KEY_USER_A");
        _USER_B_PRIVATE_KEY = vm.envUint("PRIVATE_KEY_USER_B");
        userA = vm.addr(_USER_A_PRIVATE_KEY);
        userB = vm.addr(_USER_B_PRIVATE_KEY);
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        IERC20 fromToken = IERC20(strategy.reward());
        IERC20 toToken = IERC20(strategy.asset());
        uint256 fromAmount = fromToken.balanceOf(address(strategy));

        UniswapV2Aggregator.Quote memory quote = uniswapAggregator.quote(
            fromAmount,
            address(fromToken),
            address(toToken)
        );
        uint256 slippageBips = 20;
        uint256 toAmount = (quote.quoteAmount * (10000 - slippageBips)) / 10000;

        // Build digest (in reality, do this by looking at signature logs)
        ISettlement.Interaction[] memory preHooks;
        ISettlement.Interaction[]
            memory postHooks = new ISettlement.Interaction[](1);
        postHooks[0] = ISettlement.Interaction({
            target: address(strategy),
            value: 0,
            callData: abi.encodeWithSignature("updateAccounting()")
        });
        ISettlement.Hooks memory hooks = ISettlement.Hooks({
            preHooks: preHooks,
            postHooks: postHooks
        });
        ISettlement.Payload memory decodedPayload = ISettlement.Payload({
            fromToken: usdc,
            toToken: dai,
            fromAmount: 3000000,
            toAmount: 2970257895415816631,
            sender: address(strategy),
            recipient: address(strategy),
            nonce: 0,
            deadline: 1686175288,
            hooks: hooks
        });

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
        bytes32 s = bytes32(uint256(0x60)); // offset - 96. 0x00 is strategy, 0x20 is s, 0x40 is v 0x60 is length 0x 80 is data
        bytes32 v = bytes32(uint256(0)); // type zero - contract sig
        bytes memory encodedSignatures = abi.encodePacked(
            abi.encode(strategy, s, v, signatures.length),
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
