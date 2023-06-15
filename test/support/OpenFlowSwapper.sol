// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;
import {IERC20} from "../../src/interfaces/IERC20.sol";
import {ISettlement} from "../../src/interfaces/ISettlement.sol";
import {IMultisigOrderManager} from "../../src/interfaces/IMultisigOrderManager.sol";
import {IOracle} from "../../src/interfaces/IOracle.sol";
import {IStrategy} from "../../test/interfaces/IStrategy.sol";

/// @author OpenFlow
/// @title OpenFlow Swapper
/// @notice Implements an example of on-chain swap order submission for OpenFlow multisig authenticated auctions
/// @dev Responsible submitting swap orders. Supports EIP-1271 signature validation by delegating signature
/// validation requests to MultisigOrderManager
contract OpenFlowSwapper {
    /// @dev Magic value per EIP-1271 to be returned upon successful validation
    bytes4 private constant _EIP1271_MAGICVALUE = 0x1626ba7e;

    /// @dev Multisig order manager is responsible for signature validation and actual order submission
    address _multisigOrderManager;

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
        address multisigOrderManager,
        address fromToken,
        address toToken
    ) {
        _multisigOrderManager = multisigOrderManager;
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

    /// @notice Determine whether or not a signature is valid
    /// @dev In this case we leverage Multisig Order Manager to ensure two things:
    /// - 1. The digest is approved (and not invalidated)
    /// - 2. The swap has been approved by multisig (to ensure best quote was selected)
    /// @param digest The digest of the order payload
    /// @param signatures Encoded EIP-1271 signatures formatted per Gnosis
    function isValidSignature(
        bytes32 digest,
        bytes calldata signatures
    ) external returns (bytes4) {
        IMultisigOrderManager(_multisigOrderManager).checkNSignatures(
            digest,
            signatures
        );
        require(
            IMultisigOrderManager(_multisigOrderManager).digestApproved(
                address(this),
                digest
            ),
            "Digest not approved"
        );
        return _EIP1271_MAGICVALUE;
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
        IMultisigOrderManager(_multisigOrderManager).submitOrder(
            ISettlement.Payload({
                fromToken: address(_fromToken),
                toToken: address(_toToken),
                fromAmount: fromAmount,
                toAmount: minAmountOut,
                sender: address(this),
                recipient: address(this),
                deadline: uint32(block.timestamp + _maxAuctionDuration),
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
