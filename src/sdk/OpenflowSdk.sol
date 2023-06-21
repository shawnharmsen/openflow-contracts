// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;
import {ISettlement} from "../interfaces/ISettlement.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {IOracle} from "../interfaces/IOracle.sol";
import {OrderDelegator} from "./OrderDelegator.sol";

contract OpenflowSdk is OrderDelegator {
    /// @notice Initialize SDK.
    /// @dev Can only be initialized once.
    /// @dev SDK is automatically initialized during instance creation.
    function initialize(
        address _settlement,
        address _manager,
        address _sender,
        address _recipient
    ) external {
        _initialize(_settlement, _manager, _sender, _recipient);
    }

    /*******************************************************
     * Order creation
     *******************************************************/
    /// @notice Fully configurable swap
    /// @param payload Complete swap payload
    /// @dev If not all options are set in payload defaults will be used
    /// @return orderUid UID of the order
    function submitOrder(
        ISettlement.Payload memory payload
    ) external returns (bytes memory orderUid) {
        orderUid = _submitOrder(payload);
    }

    /// @notice Simple swap alias
    /// @param fromToken Token to swap from
    /// @param toToken Token to swap to
    /// @return orderUid UID of the order
    function swap(
        address fromToken,
        address toToken
    ) public returns (bytes memory orderUid) {
        ISettlement.Payload memory payload;
        payload.fromToken = fromToken;
        payload.toToken = toToken;
        orderUid = _submitOrder(payload);
    }

    /// @notice Sell as price of fromToken goes up
    /// TODO: Implement
    /// @param fromToken Token to swap from
    /// @param toToken Token to swap to
    /// @return orderUid UID of the order
    function incrementalSwap(
        address fromToken,
        address toToken,
        uint256 targetPrice,
        uint256 stopLossPrice,
        uint256 steps
    ) public returns (bytes memory orderUid) {}

    /// @notice Sell as price of fromToken goes up
    /// TODO: Implement
    /// @param fromToken Token to swap from
    /// @param toToken Token to swap to
    /// @return orderUid UID of the order
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
    /// @return orderUid UID of the order
    function gatSwap(
        address fromToken,
        address toToken,
        uint32 validFrom
    ) public returns (bytes memory orderUid) {
        ISettlement.Payload memory payload;
        payload.fromToken = fromToken;
        payload.toToken = toToken;
        payload.validFrom = validFrom;
        orderUid = _submitOrder(payload);
    }

    /// @notice Alias to sell token only if a certain condition is met
    /// @param fromToken Token to swap from
    /// @param toToken Token to swap to
    /// @param fromToken Token to swap from
    /// @param condition Condition which must be met for a swap to succeed
    /// @return orderUid UID of the order
    function conditionalSwap(
        address fromToken,
        address toToken,
        ISettlement.Condition memory condition
    ) public returns (bytes memory orderUid) {
        ISettlement.Payload memory payload;
        payload.fromToken = fromToken;
        payload.toToken = toToken;
        payload.condition = condition;
        orderUid = _submitOrder(payload);
    }

    /// @notice Internal swap method
    /// @dev Responsible for authentication and default param selection
    /// @param payload Order payload
    /// @return orderUid UID of the order
    function _submitOrder(
        ISettlement.Payload memory payload
    ) internal auth returns (bytes memory orderUid) {
        if (payload.recipient == address(0)) {
            payload.recipient = options.recipient;
        }
        if (payload.fromAmount == 0) {
            payload.fromAmount = IERC20(payload.fromToken).balanceOf(
                options.sender
            );
        }

        payload.hooks.preHooks = _appendTransferToPreswapHooks(
            payload.hooks.preHooks,
            payload.fromToken,
            payload.fromAmount
        );
        payload.sender = address(this);
        if (payload.toAmount == 0) {
            try
                IOracle(options.oracle).calculateEquivalentAmountAfterSlippage(
                    payload.fromToken,
                    payload.toToken,
                    payload.fromAmount,
                    options.slippageBips
                )
            returns (uint256 toAmount) {
                payload.toAmount = toAmount;
            } catch {
                if (options.requireOracle) {
                    revert("Oracle is not able to find an appropriate price");
                }
            }
        }
        if (payload.validFrom == 0) {
            payload.validFrom = uint32(block.timestamp);
        }
        if (payload.validTo == 0) {
            uint256 auctionDuration = options.auctionDuration;
            payload.validTo = uint32(payload.validFrom + auctionDuration);
        }
        if (payload.driver == address(0)) {
            payload.driver = options.driver;
        }
        payload.scheme = ISettlement.Scheme.PreSign;
        orderUid = ISettlement(settlement).submitOrder(payload);
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
}
