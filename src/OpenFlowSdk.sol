// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;
import {IERC20} from "./interfaces/IERC20.sol";
import {ISettlement} from "./interfaces/ISettlement.sol";
import {IOracle} from "./interfaces/IOracle.sol";

contract OpenflowSdkStorage {
    struct SwapConfig {
        address driver; // Driver is responsible for authenticating quote selection
        address oracle; // Oracle is responsible for determining minimum amount out for an order
        uint256 slippageBips; // Acceptable slippage threshold denoted in BIPs
        uint256 auctionDuration; // Maximum duration for auction
        address manager;
    }
    address public settlement;
    SwapConfig public swapConfig;

    constructor(address _settlement) {
        settlement = _settlement;
        swapConfig.driver = ISettlement(_settlement).defaultDriver();
        swapConfig.oracle = ISettlement(_settlement).defaultOracle();
        swapConfig.slippageBips = 150;
        swapConfig.manager = msg.sender;
    }

    function setSwapConfig(SwapConfig memory _swapConfig) external onlyManager {
        swapConfig = _swapConfig;
    }

    modifier onlyManager() {
        require(
            msg.sender == swapConfig.manager,
            "Only the swap manager can call this function."
        );
        _;
    }
}

contract OpenflowSdk is OpenflowSdkStorage {
    constructor(address _settlement) OpenflowSdkStorage(_settlement) {}

    // Basic swaps
    function _swap(address fromToken, address toToken) internal {
        ISettlement.Payload memory payload;
        payload.fromToken = fromToken;
        payload.toToken = toToken;
        _submitOrder(payload);
    }

    function _submitOrder(ISettlement.Payload memory payload) internal {
        if (payload.sender == address(0)) {
            payload.sender = address(this);
        }
        if (payload.recipient == address(0)) {
            payload.recipient = address(this);
        }
        if (payload.fromAmount == 0) {
            payload.fromAmount = IERC20(payload.fromToken).balanceOf(
                payload.sender
            );
        }
        if (payload.toAmount == 0 && swapConfig.oracle != address(0)) {
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
            uint256 auctionDuration = swapConfig.auctionDuration;
            payload.validTo = uint32(block.timestamp + auctionDuration);
        }
        if (payload.driver == address(0)) {
            payload.driver = swapConfig.driver;
        }
        payload.scheme = ISettlement.Scheme.PreSign;
        ISettlement(settlement).submitOrder(payload);
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
        minimumAmountOut = IOracle(swapConfig.oracle)
            .calculateEquivalentAmountAfterSlippage(
                fromToken,
                toToken,
                fromAmount,
                swapConfig.slippageBips
            );
    }
}
