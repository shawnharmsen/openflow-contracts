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
        Strategy(0x96F71aDc0302907761Fa7C9a91f961fB1Be7230c);
    Oracle public oracle = Oracle(0xaCcd3564e9fF00DE2a96ACfD6A97C1a9865596b1);
    MasterChef public masterChef =
        MasterChef(0x7e5CDA51741f38C63FDf3C40Ed48Adc005caC1a3);
    address public usdc = 0x04068DA6C83AFCFA0e13ba15A6696662335D5B75;
    address public dai = 0x8D11eC38a3EB5E956B052f67Da8Bdc9bef8Abf3E;
    address public weth = 0x74b23882a30290451A17c44f4F05243b6b58C76d;
    Settlement public settlement =
        Settlement(0xED2dcEF4cA23eE6b75EaF71E07907b07869b5E1F);
    OrderExecutor public executor =
        OrderExecutor(0xF24404E17CCFFcbfC74f6267080AB73bB619125c);
    UniswapV2Aggregator public uniswapAggregator =
        UniswapV2Aggregator(0xC2c76012fe0e41420840083CCA19AB5c1179da4F);
    MultisigOrderManager public multisigOrderManager =
        MultisigOrderManager(0x3a8FF5820D43782A63c76F361812fF5D308A884a);

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
            fromAmount: 1000000,
            toAmount: 989953775051002040,
            sender: address(strategy),
            recipient: address(strategy),
            deadline: 1686195228,
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
