// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;
import {IERC20} from "../../src/interfaces/IERC20.sol";
import {ISettlement} from "../../src/interfaces/ISettlement.sol";
import {MultisigOrderManager} from "../../src/MultisigOrderManager.sol";
import {SimpleChainlinkOracle} from "./SimpleChainlinkOracle.sol";
import {Strategy} from "./Strategy.sol";

contract OpenFlowSwapper {
    bytes4 private constant _EIP1271_MAGICVALUE = 0x1626ba7e;
    MultisigOrderManager _multisigOrderManager;
    SimpleChainlinkOracle _oracle;
    address internal _fromToken;
    address internal _toToken;

    constructor(
        MultisigOrderManager multisigOrderManager,
        SimpleChainlinkOracle oracle,
        address fromToken,
        address toToken
    ) {
        _multisigOrderManager = multisigOrderManager;
        _fromToken = fromToken;
        _toToken = toToken;
        _oracle = oracle;
    }

    function isValidSignature(
        bytes32 digest,
        bytes calldata signatures
    ) external returns (bytes4) {
        _multisigOrderManager.checkNSignatures(digest, signatures);
        require(
            _multisigOrderManager.digestApproved(digest),
            "Digest not approved"
        );
        return _EIP1271_MAGICVALUE;
    }

    function _swap() internal {
        // Determine swap amounts
        uint256 fromAmount = IERC20(_fromToken).balanceOf(address(this));
        uint256 slippageBips = 30; // 0.3%
        uint256 minAmountOut = _oracle.calculateEquivalentAmountAfterSlippage(
            _fromToken,
            _toToken,
            fromAmount,
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
        _multisigOrderManager.submitOrder(
            ISettlement.Payload({
                fromToken: address(_fromToken),
                toToken: address(_toToken),
                fromAmount: fromAmount,
                toAmount: minAmountOut,
                sender: address(this),
                recipient: address(this),
                nonce: 0,
                deadline: uint32(block.timestamp),
                hooks: hooks
            })
        );
    }
}
