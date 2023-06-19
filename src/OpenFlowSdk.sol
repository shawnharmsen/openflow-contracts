// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

/*******************************************************
 * Interfaces
 *******************************************************/
import {ISettlement} from "./interfaces/ISettlement.sol";

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
}

interface IOracle {
    function calculateEquivalentAmountAfterSlippage(
        address _fromToken,
        address _toToken,
        uint256 _amountIn,
        uint256 _slippageBips
    ) external view returns (uint256 amountOut);
}

/*******************************************************
 * Storage
 *******************************************************/
contract OpenflowSdkStorage {
    struct SdkOptions {
        address driver; // Driver is responsible for authenticating quote selection
        address oracle; // Oracle is responsible for determining minimum amount out for an order
        uint256 slippageBips; // Acceptable slippage threshold denoted in BIPs
        uint256 auctionDuration; // Maximum duration for auction
        address manager; // Manager is responsible for managing swap config
    }

    SdkOptions public sdkOptions;
    address public settlement;

    constructor(address _settlement) {
        settlement = _settlement;
        sdkOptions.driver = ISettlement(_settlement).defaultDriver();
        sdkOptions.oracle = ISettlement(_settlement).defaultOracle();
        sdkOptions.slippageBips = 150;
        sdkOptions.manager = msg.sender;
    }

    function setSwapConfig(SdkOptions memory _swapConfig) public onlyManager {
        sdkOptions = _swapConfig;
    }

    modifier onlyManager() {
        require(
            msg.sender == sdkOptions.manager,
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
            payload.validTo = uint32(block.timestamp + auctionDuration);
        }
        if (payload.driver == address(0)) {
            payload.driver = sdkOptions.driver;
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
        minimumAmountOut = IOracle(sdkOptions.oracle)
            .calculateEquivalentAmountAfterSlippage(
                fromToken,
                toToken,
                fromAmount,
                sdkOptions.slippageBips
            );
    }
}
