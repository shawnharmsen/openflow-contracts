// SPDX-License-Identifier: BUSL 1.1
pragma solidity 0.8.19;
import "./interfaces/ISettlement.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/ISignatureManager.sol";
import "./interfaces/IEip1271SignatureValidator.sol";
import {SafeTransferLib, ERC20} from "solmate/utils/SafeTransferLib.sol";
import {SigningLib} from "./lib/Signing.sol";

/// @author OpenFlow
/// @title Settlement
/// @dev Settlement is the primary contract for swap execution. The concept is simple.
/// - User approves Settlement to spend fromToken
/// - User submits a request for quotes (RFQ) and solvers submit quotes
/// - User selects the best quote and user creates a signed order for the swap based on the quote
/// - Once an order is signed anyone with the signature and payload can execute the order
/// - The solver whose quote was selected receives the signature and initiates a signed order execution
/// - Order `fromToken` is transferred from the order signer to the order executor (order executor is solver configurable)
/// - Order executor executes the swap in whatever way they see fit
/// - At the end of the swap the user's `toToken` delta must be greater than or equal to the agreed upon `toAmount`
contract Settlement {
    /// @dev Use SafeTransfer for all ERC20 operations
    using SafeTransferLib for ERC20;

    /// @dev Prepare constants for building domainSeparator
    bytes32 private constant _DOMAIN_NAME = keccak256("Blockswap");
    bytes32 private constant _DOMAIN_VERSION = keccak256("v0.0.1");
    bytes32 private constant _DOMAIN_TYPE_HASH =
        keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        );
    bytes32 public constant TYPE_HASH =
        keccak256(
            "Payload(address fromToken,address toToken,uint256 fromAmount,uint256 toAmount,address sender,address recipient,uint256 deadline)"
        );
    bytes32 public immutable domainSeparator;

    /// @dev When an order has been filled the order UID fill mapping below must be set to true
    mapping(bytes => bool) public orderFilledByUid;

    /// @dev Contracts are allowed to submit pre-swap and post-swap hooks along with their order.
    /// For security purposes all hooks are executed via a simople execution proxy to disallow sending
    /// arbitrary calls directly from the context of Settlement. This is done because Settlement is the
    /// primary contract upon which token allowances will be set.
    ExecutionProxy _executionProxy;

    /// @dev When an order has been executed successfully emit an event
    event OrderExecuted(
        address solver,
        address executor,
        address sender,
        address recipient,
        address fromToken,
        address toToken,
        uint256 fromAmount,
        uint256 toAmount
    );

    /// @dev Set domainSeparator and _executionProxy
    constructor() {
        domainSeparator = keccak256(
            abi.encode(
                _DOMAIN_TYPE_HASH,
                _DOMAIN_NAME,
                _DOMAIN_VERSION,
                block.chainid,
                address(this)
            )
        );
        _executionProxy = new ExecutionProxy();
    }

    /// @notice Primary method for order execution
    /// @dev TODO: Analyze whether or not this needs to be non-reentrant
    /// @param order The order to execute
    function executeOrder(ISettlement.Order calldata order) public {
        ISettlement.Payload memory payload = order.payload;

        /// @notice Step 1. Verify the integrity of the order
        /// @dev Verifies that payload.sender signed the order
        /// @dev Only the order payload is signed
        /// @dev Once an order is signed anyone who has the signature can fufil the order
        /// @dev In the case of smart contracts sender must implement EIP-1271 isVerified method
        _verify(order);

        /// @notice Step 2. Execute optional contract preswap hooks
        _execute(order.payload.hooks.preHooks);

        /// @notice Step 3. Optimistically transfer funds from payload.sender to msg.sender (order executor)
        /// @dev Payload.sender must approve settlement
        /// @dev TODO: We probably don't need safe transfer anymore here since we are checking balances now
        ERC20(payload.fromToken).safeTransferFrom(
            payload.sender,
            msg.sender,
            payload.fromAmount
        );
        uint256 outputTokenBalanceBefore = ERC20(payload.toToken).balanceOf(
            payload.recipient
        );

        /// @notice Step 4. Order executor executes the swap and is required to send funds to payload.recipient
        /// @dev Order executors can be completely custom, or the generic order executor can be used
        /// @dev Solver configurable metadata about the order is sent to the order executor hook
        /// @dev Settlement does not care how the solver executes the order, all Settlement cares about is that
        /// the user receives the minimum amount of tokens the signer agreed to
        ISolver(msg.sender).hook(order.data);

        /// @notice Step 5. Execute optional contract postswap hooks
        _execute(order.payload.hooks.postHooks);

        /// @notice Step 6. Make sure payload.recipient receives the agreed upon amount of tokens
        uint256 outputTokenBalanceAfter = ERC20(payload.toToken).balanceOf(
            payload.recipient
        );
        uint256 balanceDelta = outputTokenBalanceAfter -
            outputTokenBalanceBefore;
        require(balanceDelta >= payload.toAmount, "Order not filled");

        /// @dev Emit OrderExecuted
        emit OrderExecuted(
            tx.origin,
            msg.sender,
            payload.sender,
            payload.recipient,
            payload.fromToken,
            payload.toToken,
            payload.fromAmount,
            balanceDelta
        );
    }

    /// @notice Pass hook execution interactions to execution proxy to be executed
    /// @param interactions The interactions to execute
    function _execute(ISettlement.Interaction[] memory interactions) internal {
        if (interactions.length > 0) {
            _executionProxy.execute(interactions);
        }
    }

    /// @notice Order verification
    /// @dev Verify the order
    /// @dev Signature type is auto-detected based on signature's v
    /// see: Gnosis Safe implementationa.
    /// @dev Supports:
    /// - EIP-712 (Structured EOA signatures)
    /// - EIP-1271 (Contract based signatures)
    /// - EthSign (Non-structured EOA signatures)
    function _verify(ISettlement.Order calldata order) internal {
        bytes32 digest = buildDigest(order.payload);
        address signatory = SigningLib.recoverSigner(order.signature, digest);
        require(signatory == order.payload.sender, "Invalid signer");
        require(block.timestamp <= order.payload.deadline, "Deadline expired");
        require(
            order.payload.nonce == nonces[signatory]++,
            "Nonce already used"
        );
    }

    /// @notice Building the digest hash
    /// @dev Message digest hash consists of type hash, domain separator and type hash
    function buildDigest(
        ISettlement.Payload memory _payload
    ) public view returns (bytes32 orderDigest) {
        bytes32 typeHash = TYPE_HASH;
        bytes32 structHash = keccak256(
            abi.encodePacked(typeHash, abi.encode(_payload))
        );
        orderDigest = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash)
        );
    }
}

/// @title Execution proxy
/// @notice Simple contract used to execute pre-swap and post-swap hooks
contract ExecutionProxy {
    function execute(ISettlement.Interaction[] memory interactions) external {
        for (uint256 i; i < interactions.length; i++) {
            ISettlement.Interaction memory interaction = interactions[i];
            (bool success, ) = interaction.target.call{
                value: interaction.value
            }(interaction.callData);
            require(success, "Interaction failed");
        }
    }
}
