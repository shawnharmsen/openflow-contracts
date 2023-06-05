// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;
import {IERC20} from "../../src/interfaces/IERC20.sol";
import {ISettlement} from "../../src/interfaces/ISettlement.sol";
import {MultisigAuction, IMultisigAuction} from "../../src/MultisigAuction.sol";
import {SimpleChainlinkOracle} from "./SimpleChainlinkOracle.sol";
import {Strategy} from "./Strategy.sol";

contract OpenFlowSwapper {
    MultisigAuction _multisigAuction;
    SimpleChainlinkOracle _oracle;
    address internal _fromToken;
    address internal _toToken;

    constructor(
        MultisigAuction multisigAuction,
        SimpleChainlinkOracle oracle,
        address fromToken,
        address toToken
    ) {
        _multisigAuction = multisigAuction;
        _fromToken = fromToken;
        _toToken = toToken;
        _oracle = oracle;
    }

    function _swap() internal {
        // Determine swap amounts
        uint256 amountIn = IERC20(_fromToken).balanceOf(address(this));
        uint256 slippageBips = 30; // 0.3%
        uint256 minAmountOut = _oracle.calculateEquivalentAmountAfterSlippage(
            _fromToken,
            _toToken,
            amountIn,
            slippageBips
        );

        // Create optional posthook
        ISettlement.Interaction[] memory preHooks;
        ISettlement.Interaction[]
            memory postHooks = new ISettlement.Interaction[](1);
        postHooks[0] = ISettlement.Interaction({
            target: address(this),
            value: 0,
            callData: abi.encodeWithSelector(Strategy.updateAccounting.selector)
        });
        ISettlement.Hooks memory hooks = ISettlement.Hooks({
            preHooks: preHooks,
            postHooks: postHooks
        });

        // Swap
        _multisigAuction.initiateSwap(
            IMultisigAuction.SwapOrder({
                fromToken: address(_fromToken),
                toToken: address(_toToken),
                amountIn: amountIn,
                minAmountOut: minAmountOut,
                recipient: address(this),
                hooks: hooks
            })
        );
    }
}