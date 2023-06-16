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

contract Storage is Script {
    // Hardcoded values. In the future read from broadcast deployment logs
    Strategy public strategy =
        Strategy(0xE4D14B428a22461C1F8A822e86691df381458440);
    Oracle public oracle = Oracle(0x233A3588972DDd57D7F19369FdE8DcEEe88B8e73);
    MasterChef public masterChef =
        MasterChef(0xFE38EE7F7228a1a278FF0d57365563a4c8c54297);
    address public usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    Settlement public settlement =
        Settlement(0xD4D94C981Cd3a88E31D4070F5aCDf561084DEe00);
    OrderExecutor public executor =
        OrderExecutor(0x09D2fB1f7f810e0099712fd2993CfFCcc53E7266);
    UniswapV2Aggregator public uniswapAggregator =
        UniswapV2Aggregator(0x5CE348a9E2c7774e92C06c5f352Eb5F5cDD002DA);
    MultisigOrderManager public multisigOrderManager =
        MultisigOrderManager(0x0B40502A7C4f72c8e7547407039f41C43310301C);

    address public userA;
    address public userB;
    uint256 internal immutable _USER_A_PRIVATE_KEY;
    uint256 internal immutable _USER_B_PRIVATE_KEY;
    uint256 deployerPrivateKey;
    IERC20 fromToken;
    IERC20 toToken;

    constructor() {
        _USER_A_PRIVATE_KEY = vm.envUint("PRIVATE_KEY_USER_A");
        _USER_B_PRIVATE_KEY = vm.envUint("PRIVATE_KEY_USER_B");
        userA = vm.addr(_USER_A_PRIVATE_KEY);
        userB = vm.addr(_USER_B_PRIVATE_KEY);
        deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        fromToken = IERC20(strategy.reward());
        toToken = IERC20(strategy.asset());
    }
}

contract Harvest is Storage {
    function run() public {
        vm.startBroadcast(deployerPrivateKey);
        fromToken.transfer(address(masterChef), 1e6);
        masterChef.accrueReward();
        strategy.harvest();
    }
}

contract Swap is Storage {
    function run() public {
        vm.startBroadcast(deployerPrivateKey);
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
            fromAmount: 2000000,
            toAmount: 1980131121398188226,
            sender: address(strategy),
            recipient: address(strategy),
            deadline: 1686297308,
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
