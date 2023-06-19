// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;
import {ISettlement} from "./interfaces/ISettlement.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {IOracle} from "./interfaces/IOracle.sol";

/*******************************************************
 * Factory
 *******************************************************/
contract OpenflowFactory {
    address public settlement;

    constructor(address _settlement) {
        settlement = _settlement;
    }

    function newSdkInstance() external returns (OpenflowSdk openflowSdk) {
        return newSdkInstance(msg.sender, msg.sender, msg.sender);
    }

    function newSdkInstance(
        address _manager
    ) external returns (OpenflowSdk openflowSdk) {
        return newSdkInstance(_manager, msg.sender, msg.sender);
    }

    function newSdkInstance(
        address _manager,
        address _sender,
        address _recipient
    ) public returns (OpenflowSdk openflowSdk) {
        return new OpenflowSdk(settlement, _manager, _sender, _recipient);
    }
}

/*******************************************************
 * Storage
 *******************************************************/
contract OpenflowSdkStorage {
    struct SdkOptions {
        address driver; // Driver is responsible for authenticating quote selection.
        address oracle; // Oracle is responsible for determining minimum amount out for an order.
        uint256 slippageBips; // Acceptable slippage threshold denoted in BIPs.
        uint256 auctionDuration; // Maximum duration for auction.
        address manager; // Manager is responsible for managing SDK options.
        address sender; // Funds will be transferred to settlement from this sender.
        address recipient; // Funds will be sent to recipient after swap.
    }

    SdkOptions public sdkOptions;
    address public settlement;
    address public executionProxy;

    constructor(
        address _settlement,
        address _manager,
        address _sender,
        address _recipient
    ) {
        settlement = _settlement;
        executionProxy = ISettlement(_settlement).executionProxy();
        sdkOptions.driver = ISettlement(_settlement).defaultDriver();
        sdkOptions.oracle = ISettlement(_settlement).defaultOracle();
        sdkOptions.slippageBips = 150;
        sdkOptions.manager = _manager;
        sdkOptions.sender = _sender;
        sdkOptions.recipient = _recipient;
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

/*******************************************************
 * Order delegator
 *******************************************************/
contract OrderDelegator is OpenflowSdkStorage {
    constructor(
        address _settlement,
        address _manager,
        address _sender,
        address _recipient
    ) OpenflowSdkStorage(_settlement, _manager, _sender, _recipient) {}

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
            sdkOptions.sender,
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

/*******************************************************
 * SDK
 *******************************************************/
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
