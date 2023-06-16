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

import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {Settlement} from "../src/Settlement.sol";
import {OrderExecutor} from "../src/executors/OrderExecutor.sol";
import {UniswapV2Aggregator} from "../src/solvers/UniswapV2Aggregator.sol";
import {ISettlement} from "../src/interfaces/ISettlement.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {YearnVaultInteractions, IVaultRegistry, IVault} from "../test/support/YearnVaultInteractions.sol";

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

    IVaultRegistry public constant vaultRegistry =
        IVaultRegistry(0x50c1a2eA0a861A967D9d0FFE2AE4012c2E053804);
    address public vaultInteractions =
        0x3C51230851C8e3d661eE7b403C5A0a03f5e81d9B;
    IERC20 public fromToken = IERC20(usdc);
    IERC20 public toToken = IERC20(weth);
    uint256 deployerPrivateKey;
    address public deployer;

    constructor() {
        deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(deployerPrivateKey);
    }
}

contract ZapIn is Storage {
    function run() public {
        vm.startBroadcast(deployerPrivateKey);

        // Get quote
        uint256 fromAmount = 1 * 1e6;
        UniswapV2Aggregator.Quote memory quote = uniswapAggregator.quote(
            fromAmount,
            address(fromToken),
            address(toToken)
        );
        uint256 toAmount = (quote.quoteAmount * 95) / 100;

        // Build hooks
        ISettlement.Interaction[] memory preHooks;
        ISettlement.Interaction[]
            memory postHooks = new ISettlement.Interaction[](1);
        postHooks[0] = ISettlement.Interaction({
            target: vaultInteractions,
            value: 0,
            callData: abi.encodeWithSignature(
                "deposit(address,address)",
                toToken,
                deployer
            )
        });
        ISettlement.Hooks memory hooks = ISettlement.Hooks({
            preHooks: preHooks,
            postHooks: postHooks
        });

        // Build paylod
        ISettlement.Payload memory payload = ISettlement.Payload({
            fromToken: address(fromToken),
            toToken: address(toToken),
            fromAmount: fromAmount,
            toAmount: toAmount,
            sender: deployer,
            recipient: vaultInteractions,
            deadline: uint32(block.timestamp) + 60 * 5,
            hooks: hooks
        });

        // Build executor data
        bytes memory executorData = abi.encode(
            OrderExecutor.Data({
                fromToken: IERC20(payload.fromToken),
                toToken: IERC20(payload.toToken),
                fromAmount: payload.fromAmount,
                toAmount: payload.toAmount,
                recipient: payload.recipient,
                target: address(uniswapAggregator),
                payload: abi.encodeWithSelector(
                    UniswapV2Aggregator.executeOrder.selector,
                    quote.routerAddress,
                    quote.path,
                    payload.fromAmount,
                    payload.toAmount
                )
            })
        );

        // Build order
        ISettlement.Order memory order = ISettlement.Order({
            signature: hex"",
            data: executorData,
            payload: payload
        });

        // Sign order
        bytes32 digest = settlement.buildDigest(order.payload);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(deployerPrivateKey, digest);
        order.signature = abi.encodePacked(r, s, v);

        // Make sure user has no yvToken
        IVault vault = IVault(vaultRegistry.latestVault(address(toToken)));
        require(vault.balanceOf(deployer) == 0, "Invalid vault start balance");

        // Grant settlement infinite allowance
        fromToken.approve(address(settlement), type(uint256).max);

        // Execute zap in
        ISettlement.Interaction[][2] memory solverInteractions;
        executor.executeOrder(order, solverInteractions);

        // Make sure zap was successful
        require(vault.balanceOf(deployer) > 0, "Invalid vault end balance");
    }
}

contract ZapOut is Storage {
    function run() external {
        vm.startBroadcast(deployerPrivateKey);

        // Swap from and to token
        IERC20 tempToken = fromToken;
        fromToken = toToken;
        toToken = tempToken;

        // Allow vault interactions to zap out (this could also be done with permit)
        IVault vault = IVault(vaultRegistry.latestVault(address(fromToken)));
        vault.approve(address(vaultInteractions), type(uint256).max);

        // Build hooks
        ISettlement.Interaction[]
            memory preHooks = new ISettlement.Interaction[](1);
        preHooks[0] = ISettlement.Interaction({
            target: vaultInteractions,
            value: 0,
            callData: abi.encodeWithSignature(
                "withdraw(address)",
                address(vault)
            )
        });
        ISettlement.Interaction[]
            memory postHooks = new ISettlement.Interaction[](0);
        ISettlement.Hooks memory hooks = ISettlement.Hooks({
            preHooks: preHooks,
            postHooks: postHooks
        });

        // Get quote
        uint256 fromAmount = (vault.balanceOf(deployer) *
            vault.pricePerShare()) / 1e18;
        UniswapV2Aggregator.Quote memory quote = uniswapAggregator.quote(
            fromAmount,
            address(fromToken),
            address(toToken)
        );
        uint256 toAmount = (quote.quoteAmount * 95) / 100;

        // Build paylod
        ISettlement.Payload memory payload = ISettlement.Payload({
            fromToken: address(fromToken),
            toToken: address(toToken),
            fromAmount: fromAmount,
            toAmount: toAmount,
            sender: deployer,
            recipient: deployer,
            deadline: uint32(block.timestamp) + 5 * 60,
            hooks: hooks
        });

        // Build executor data
        bytes memory executorData = abi.encode(
            OrderExecutor.Data({
                fromToken: IERC20(payload.fromToken),
                toToken: IERC20(payload.toToken),
                fromAmount: payload.fromAmount,
                toAmount: payload.toAmount,
                recipient: payload.recipient,
                target: address(uniswapAggregator),
                payload: abi.encodeWithSelector(
                    UniswapV2Aggregator.executeOrder.selector,
                    quote.routerAddress,
                    quote.path,
                    payload.fromAmount,
                    payload.toAmount
                )
            })
        );

        // Build order
        ISettlement.Order memory order = ISettlement.Order({
            signature: hex"",
            data: executorData,
            payload: payload
        });

        // Sign order
        bytes32 digest = settlement.buildDigest(order.payload);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(deployerPrivateKey, digest);
        order.signature = abi.encodePacked(r, s, v);

        // Execute zap out
        ISettlement.Interaction[][2] memory solverInteractions;
        executor.executeOrder(order, solverInteractions);
    }
}
