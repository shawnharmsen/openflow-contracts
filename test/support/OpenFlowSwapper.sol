// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;
import {IERC20} from "../../src/interfaces/IERC20.sol";
import {ISettlement} from "../../src/interfaces/ISettlement.sol";
import {IOrderManager} from "../../src/interfaces/IOrderManager.sol";
import {IOracle} from "../../src/interfaces/IOracle.sol";
import {IStrategy} from "../../test/interfaces/IStrategy.sol";

/// @author OpenFlow
/// @title OpenFlow Swapper
/// @notice Implements an example of on-chain swap order submission for OpenFlow multisig authenticated auctions
/// @dev Responsible submitting swap orders. Supports EIP-1271 signature validation by delegating signature
/// validation requests to Driver
contract OpenFlowSwapper {
    /// @dev Magic value per EIP-1271 to be returned upon successful validation
    bytes4 private constant _EIP1271_MAGICVALUE = 0x1626ba7e;

    /// @dev TODO: comment
    address _settlement;
    address _driver;

    /// @dev Oracle responsible for determining minimum amount out for an order
    address _oracle;

    /// @dev Token to swap from
    address internal _fromToken;

    /// @dev Token to swap to
    address internal _toToken;

    /// @dev Acceptable slippage threshold denoted in BIPs
    uint256 internal _slippageBips;

    /// @dev Maximum duration for auction
    uint256 internal _maxAuctionDuration;

    constructor(
        address driver,
        address settlement,
        address fromToken,
        address toToken
    ) {
        _driver = driver;
        _settlement = settlement;
        _fromToken = fromToken;
        _toToken = toToken;
    }

    /// @notice Only allow strategy manager to configure swap parameters
    modifier onlyManager() {
        require(
            msg.sender == IStrategy(address(this)).manager(),
            "Only the owner can call this function."
        );
        _;
    }

    /// @notice Initiate a swap using this contract's complete balance of `fromToken`
    /// @dev Calculates appropriate minimumAmountOut, defines any pre/post swap hooks
    /// and submits the order. Submitting the order will sign the digest in
    /// Multisig Order Management and emit an event, triggering a new auction.
    function _swap() internal {
        // Determine swap amounts
        uint256 fromAmount = IERC20(_fromToken).balanceOf(address(this));
        uint256 minAmountOut = IOracle(_oracle)
            .calculateEquivalentAmountAfterSlippage(
                _fromToken,
                _toToken,
                fromAmount,
                _slippageBips
            );

        // Create optional posthook
        ISettlement.Interaction[] memory preHooks;
        ISettlement.Interaction[]
            memory postHooks = new ISettlement.Interaction[](1);
        postHooks[0] = ISettlement.Interaction({
            target: address(this),
            value: 0,
            callData: abi.encodeWithSignature("updateAccounting()")
        });
        ISettlement.Hooks memory hooks = ISettlement.Hooks({
            preHooks: preHooks,
            postHooks: postHooks
        });

        // Swap
        IOrderManager(_settlement).submitOrder(
            ISettlement.Payload({
                fromToken: address(_fromToken),
                toToken: address(_toToken),
                fromAmount: fromAmount,
                toAmount: minAmountOut,
                sender: address(this),
                recipient: address(this),
                deadline: uint32(block.timestamp + _maxAuctionDuration),
                scheme: ISettlement.Scheme.PreSign,
                driver: ISettlement(_settlement).defaultDriver(),
                hooks: hooks
            })
        );
    }

    /// @notice Set auction duration
    /// @param duration (in seconds)
    function setMaxAuctionDuration(uint256 duration) external onlyManager {
        _maxAuctionDuration = duration;
    }

    /// @notice Set slippage
    /// @param slippageBips Amount of allowed slippage
    function setSlippage(uint256 slippageBips) external onlyManager {
        _slippageBips = slippageBips;
    }

    /// @notice Set oracle
    /// @param oracle Oracle address
    function setOracle(address oracle) external onlyManager {
        _oracle = oracle;
    }
}
