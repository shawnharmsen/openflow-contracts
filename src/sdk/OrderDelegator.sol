// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;
import {SdkStorage} from "./SdkStorage.sol";
import {ISettlement} from "../interfaces/ISettlement.sol";
import {IERC20} from "../interfaces/IERC20.sol";

contract OrderDelegator is SdkStorage {
    /// @notice Transfer funds from authenticated sender to settlement.
    /// @dev This function is only callable when sent as a pre-swap hook from
    /// executionProxy, where sender is authenticated with signature
    /// verification in settlement.
    function transferToSettlement(
        address sender,
        address fromToken,
        uint256 fromAmount
    ) external {
        require(msg.sender == executionProxy, "Only execution proxy");
        address signatory;
        assembly {
            signatory := shr(96, calldataload(sub(calldatasize(), 20)))
        }
        require(
            signatory == address(this),
            "Transfer must be initiated from SDK"
        );
        IERC20(fromToken).transferFrom(sender, settlement, fromAmount);
    }

    function _appendTransferToPreswapHooks(
        ISettlement.Interaction[] memory existingHooks,
        address fromToken,
        uint256 fromAmount
    ) internal view returns (ISettlement.Interaction[] memory appendedHooks) {
        bytes memory transferToSettlementData = abi.encodeWithSignature(
            "transferToSettlement(address,address,uint256)",
            options.sender,
            fromToken,
            fromAmount
        );
        appendedHooks = new ISettlement.Interaction[](existingHooks.length + 1);
        for (
            uint256 preswapHookIdx;
            preswapHookIdx < existingHooks.length;
            preswapHookIdx++
        ) {
            appendedHooks[preswapHookIdx] = existingHooks[preswapHookIdx];
        }
        appendedHooks[existingHooks.length] = ISettlement.Interaction({
            target: address(this),
            data: transferToSettlementData,
            value: 0
        });
        return appendedHooks;
    }
}
