// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;
import {ISettlement} from "../interfaces/ISettlement.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {IOracle} from "../interfaces/IOracle.sol";
import {OrderDelegator} from "./OrderDelegator.sol";

contract OpenflowSdk is OrderDelegator {
    constructor(
        address _settlement,
        address _manager,
        address _sender,
        address _recipient
    ) OrderDelegator(_settlement, _manager, _sender, _recipient) {}

    /*******************************************************
     * Order creation
     *******************************************************/
    // Fully configurable swap
    function submitOrder(
        ISettlement.Payload memory payload
    ) public returns (bytes memory orderUid) {
        if (payload.recipient == address(0)) {
            payload.recipient = sdkOptions.recipient;
        }
        if (payload.fromAmount == 0) {
            payload.fromAmount = IERC20(payload.fromToken).balanceOf(
                sdkOptions.sender
            );
        }

        payload.hooks.preHooks = _appendTransferToPreswapHooks(
            payload.hooks.preHooks,
            payload.fromToken,
            payload.fromAmount
        );
        payload.sender = address(this);
        if (payload.toAmount == 0 && sdkOptions.oracle != address(0)) {
            payload.toAmount = calculateMininumAmountOut(
                payload.fromToken,
                payload.toToken,
                payload.fromAmount
            );
        }
        if (payload.validFrom == 0) {
            payload.validFrom = uint32(block.timestamp);
        }
        if (payload.validTo == 0) {
            uint256 auctionDuration = sdkOptions.auctionDuration;
            payload.validTo = uint32(payload.validFrom + auctionDuration);
        }
        if (payload.driver == address(0)) {
            payload.driver = sdkOptions.driver;
        }
        payload.scheme = ISettlement.Scheme.PreSign;
        orderUid = ISettlement(settlement).submitOrder(payload);
    }

    /// @notice Simple swap alias
    /// @param fromToken Token to swap from
    /// @param toToken Token to swap to
    function swap(
        address fromToken,
        address toToken
    ) public returns (bytes memory orderUid) {
        ISettlement.Payload memory payload;
        payload.fromToken = fromToken;
        payload.toToken = toToken;
        orderUid = submitOrder(payload);
    }

    /// @notice Sell as price of fromToken goes up
    /// TODO: Implement
    function incrementalSwap(
        address fromToken,
        address toToken,
        uint256 targetPrice,
        uint256 stopLossPrice,
        uint256 steps
    ) public returns (bytes memory orderUid) {}

    /// @notice Sell as price of fromToken goes up
    /// TODO: Implement
    function dcaSwap(
        address fromToken,
        address toToken,
        uint256 targetPrice,
        uint256 stopLossPrice,
        uint256 steps
    ) public returns (bytes memory orderUid) {}

    /// @notice Alias to sell token only after a certain time
    /// @param fromToken Token to swap from
    /// @param toToken Token to swap to
    /// @param validFrom Unix timestamp from which to start the auction
    function gatSwap(
        address fromToken,
        address toToken,
        uint32 validFrom
    ) public returns (bytes memory orderUid) {
        ISettlement.Payload memory payload;
        payload.fromToken = fromToken;
        payload.toToken = toToken;
        payload.validFrom = validFrom;
        orderUid = submitOrder(payload);
    }

    /// @notice Alias to sell token only if a certain condition is met
    /// @param fromToken Token to swap from
    /// @param toToken Token to swap to
    /// @param fromToken Token to swap from
    /// @param condition Condition which must be met for a swap to succeed
    function conditionalSwap(
        address fromToken,
        address toToken,
        ISettlement.Condition memory condition
    ) public returns (bytes memory orderUid) {
        ISettlement.Payload memory payload;
        payload.fromToken = fromToken;
        payload.toToken = toToken;
        payload.condition = condition;
        orderUid = submitOrder(payload);
    }

    /*******************************************************
     * Order Invalidation
     *******************************************************/
    function invalidateOrder(bytes memory orderUid) external onlyManager {
        ISettlement(settlement).invalidateOrder(orderUid);
    }

    function invalidateAllOrders() external onlyManager {
        ISettlement(settlement).invalidateAllOrders();
    }

    /// @notice Calculate minimum amount out using configured oracle
    function calculateMininumAmountOut(
        address fromToken,
        address toToken,
        uint256 fromAmount
    ) public view returns (uint256 minimumAmountOut) {
        minimumAmountOut = IOracle(sdkOptions.oracle)
            .calculateEquivalentAmountAfterSlippage(
                fromToken,
                toToken,
                fromAmount,
                sdkOptions.slippageBips
            );
    }
}
