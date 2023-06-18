// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;
import {IERC20} from "./interfaces/IERC20.sol";
import {ISettlement} from "./interfaces/ISettlement.sol";
import {IOrderManager} from "./interfaces/IOrderManager.sol";
import {IOracle} from "./interfaces/IOracle.sol";
import {IStrategy} from "../test/interfaces/IStrategy.sol";
import {IOpenFlowSdk} from "./interfaces/IOpenFlowSdk.sol";

contract OpenFlowSdkStorage is IOpenFlowSdk {
    address settlement;
    SwapConfig public swapConfig;

    constructor(address _settlement) {
        settlement = _settlement;
        swapConfig.driver = ISettlement(_settlement).defaultDriver();
        swapConfig.oracle = ISettlement(_settlement).defaultOracle();
        swapConfig.slippageBips = 150;
    }

    function setSwapConfig(SwapConfig memory _swapConfig) external onlyManager {
        swapConfig = _swapConfig;
    }

    modifier onlyManager() {
        require(
            msg.sender == IStrategy(address(this)).manager(),
            "Only the swap manager can call this function."
        );
        _;
    }
}

contract OpenFlowSdk is OpenFlowSdkStorage {
    constructor(address _settlement) OpenFlowSdkStorage(_settlement) {}

    /******************************************
     * READ
     ******************************************/

    function calculateMininumAmountOut(
        address fromToken,
        address toToken,
        uint256 fromAmount
    ) public view returns (uint256 minimumAmountOut) {
        minimumAmountOut = IOracle(swapConfig.oracle)
            .calculateEquivalentAmountAfterSlippage(
                fromToken,
                toToken,
                fromAmount,
                swapConfig.slippageBips
            );
    }

    /******************************************
     * WRITE
     ******************************************/

    // Basic swaps
    function _swap(address fromToken, address toToken) internal {
        uint256 fromAmount = IERC20(fromToken).balanceOf(address(this));
        uint256 toAmount = calculateMininumAmountOut(
            fromToken,
            toToken,
            fromAmount
        );
        _swap(fromToken, toToken, fromAmount, toAmount);
    }

    function _swap(
        address fromToken,
        address toToken,
        uint256 fromAmount,
        uint256 toAmount
    ) internal {
        ISettlement.Hooks memory hooks;
        _swap(
            fromToken,
            toToken,
            fromAmount,
            toAmount,
            uint32(block.timestamp),
            uint32(block.timestamp + swapConfig.auctionDuration),
            hooks
        );
    }

    function _swap(
        address fromToken,
        address toToken,
        uint256 fromAmount,
        uint256 toAmount,
        uint32 validFrom,
        uint32 validTo,
        ISettlement.Hooks memory hooks
    ) internal {
        IOrderManager(settlement).submitOrder(
            ISettlement.Payload({
                fromToken: fromToken,
                toToken: toToken,
                fromAmount: fromAmount,
                toAmount: toAmount,
                sender: address(this),
                recipient: address(this),
                validFrom: validFrom,
                validTo: validTo,
                scheme: ISettlement.Scheme.PreSign,
                driver: swapConfig.driver,
                hooks: hooks
            })
        );
    }

    // Sell as price of fromToken goes up
    function _incrementalSwap(
        address fromToken,
        address toToken,
        uint256 targetPrice,
        uint256 stopLossPrice,
        uint256 steps
    ) internal {}

    // Order invalidation

    function invalidateOrder(bytes memory orderUid) external onlyManager {
        IOrderManager(settlement).invalidateOrder(orderUid);
    }

    function invalidateAllOrders() external onlyManager {
        IOrderManager(settlement).invalidateAllOrders();
    }
}
