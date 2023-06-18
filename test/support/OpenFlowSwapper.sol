// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;
import {IERC20} from "../../src/interfaces/IERC20.sol";
import {ISettlement} from "../../src/interfaces/ISettlement.sol";
import {IOrderManager} from "../../src/interfaces/IOrderManager.sol";
import {IOracle} from "../../src/interfaces/IOracle.sol";
import {IStrategy} from "../../test/interfaces/IStrategy.sol";
import {IOpenFlowSwapper} from "../../src/interfaces/IOpenFlowSwapper.sol";

/// @author OpenFlow
/// @title OpenFlow Swapper
/// @notice Implements an example of on-chain swap order submission for OpenFlow multisig authenticated auctions
/// @dev Responsible submitting swap orders. Supports EIP-1271 signature validation by delegating signature
/// validation requests to Driver
contract OpenFlowSwapper is IOpenFlowSwapper {
    /// @dev Magic value per EIP-1271 to be returned upon successful validation
    bytes4 private constant _EIP1271_MAGICVALUE = 0x1626ba7e;

    /// @dev TODO: comment
    address internal _settlement;

    SwapConfig public swapConfig;

    /// @dev Token to swap from
    address internal _fromToken;

    /// @dev Token to swap to
    address internal _toToken;

    constructor(address settlement, address fromToken, address toToken) {
        _settlement = settlement;
        _fromToken = fromToken;
        _toToken = toToken;
        swapConfig.driver = ISettlement(settlement).defaultDriver();
        swapConfig.oracle = ISettlement(settlement).defaultOracle();
        swapConfig.slippageBips = 150;
    }

    /// @notice Initiate a swap using this contract's complete balance of `fromToken`
    /// @dev Calculates appropriate minimumAmountOut, defines any pre/post swap hooks
    /// and submits the order. Submitting the order will sign the digest in
    /// Multisig Order Management and emit an event, triggering a new auction.
    function _swap() internal {
        // Determine swap amounts
        uint256 fromAmount = IERC20(_fromToken).balanceOf(address(this));
        uint256 minAmountOut = IOracle(swapConfig.oracle)
            .calculateEquivalentAmountAfterSlippage(
                _fromToken,
                _toToken,
                fromAmount,
                swapConfig.slippageBips
            );

        // Swap
        ISettlement.Hooks memory hooks;
        IOrderManager(_settlement).submitOrder(
            ISettlement.Payload({
                fromToken: address(_fromToken),
                toToken: address(_toToken),
                fromAmount: fromAmount,
                toAmount: minAmountOut,
                sender: address(this),
                recipient: address(this),
                validFrom: uint32(block.timestamp),
                validTo: uint32(block.timestamp + swapConfig.auctionDuration),
                scheme: ISettlement.Scheme.PreSign,
                driver: swapConfig.driver,
                hooks: hooks
            })
        );
    }

    function invalidateOrder(bytes memory orderUid) external onlyManager {
        IOrderManager(_settlement).invalidateOrder(orderUid);
    }

    function invalidateAllOrders() external onlyManager {
        IOrderManager(_settlement).invalidateAllOrders();
    }

    function setSwapConfig(
        IOpenFlowSwapper.SwapConfig memory _swapConfig
    ) external onlyManager {
        swapConfig = _swapConfig;
    }

    /// @notice Only allow strategy manager to configure swap parameters
    modifier onlyManager() {
        require(
            msg.sender == IStrategy(address(this)).manager(),
            "Only the swap manager can call this function."
        );
        _;
    }
}
