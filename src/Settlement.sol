// SPDX-License-Identifier: BUSL 1.1
pragma solidity 0.8.19;
import "./interfaces/ISettlement.sol";
import "./interfaces/IERC20.sol";
import {SigningLib} from "./lib/Signing.sol";
import {OrderLib} from "./lib/Order.sol";

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
    /// @dev Use OrderLib for order UID encoding/decoding
    using OrderLib for bytes;

    /// @dev Prepare constants for building domainSeparator
    bytes32 private constant _DOMAIN_NAME = keccak256("Blockswap"); // TODO: Rename
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

    /// @dev Map each user order by UID to the amount that has been filled
    mapping(bytes => uint256) public filledAmount;

    /// @dev Contracts are allowed to submit pre-swap and post-swap hooks along with their order.
    /// For security purposes all hooks are executed via a simple execution proxy to disallow sending
    /// arbitrary calls directly from the context of Settlement. This is done because Settlement is the
    /// primary contract upon which token allowances will be set.
    ExecutionProxy public executionProxy;

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

    /// @dev Set domainSeparator and executionProxy
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
        executionProxy = new ExecutionProxy();
    }

    /// @notice Primary method for order execution
    /// @dev TODO: Analyze whether or not this needs to be non-reentrant
    /// @param order The order to execute
    function executeOrder(ISettlement.Order calldata order) public {
        ISettlement.Payload memory payload = order.payload;
        address signatory = payload.sender;

        /// @notice Step 1. Verify the integrity of the order
        /// @dev Verifies that payload.sender signed the order
        /// @dev Only the order payload is signed
        /// @dev Once an order is signed anyone who has the signature can fulfil the order
        /// @dev In the case of smart contracts sender must implement EIP-1271 isVerified method
        bytes memory orderUid = _verify(order);

        /// @notice Step 2. Execute optional contract pre-swap hooks
        _execute(payload.sender, order.payload.hooks.preHooks);

        /// @notice Step 3. Optimistically transfer funds from payload.sender to msg.sender (order executor)
        /// @dev Payload.sender must approve settlement.
        /// @dev If settlement already has `fromAmount` of `inputToken` send balance from Settlement.
        /// Otherwise send balance from payload.sender. The reason we do this is because the user may specify
        /// pre-swap hooks such as withdrawing from a vault (and sending tokens to Settlement) before executing the swap.
        uint256 inputTokenBalanceSettlement = IERC20(payload.fromToken)
            .balanceOf(address(this));
        if (inputTokenBalanceSettlement >= payload.fromAmount) {
            IERC20(payload.fromToken).transfer(msg.sender, payload.fromAmount);
        } else {
            IERC20(payload.fromToken).transferFrom(
                signatory,
                msg.sender,
                payload.fromAmount
            );
        }

        /// @notice Step 4. Order executor executes the swap and is required to send funds to payload.recipient
        /// @dev Order executors can be completely custom, or the generic order executor can be used
        /// @dev Solver configurable metadata about the order is sent to the order executor hook
        /// @dev Settlement does not care how the solver executes the order, all Settlement cares about is that
        /// the user receives the minimum amount of tokens the signer agreed to
        /// @dev Record output token balance before so we can ensure recipient
        /// received at least the agreed upon number of output tokens
        uint256 outputTokenBalanceBefore = IERC20(payload.toToken).balanceOf(
            payload.recipient
        );
        ISolver(msg.sender).hook(order.data);

        /// @notice Step 5. Make sure payload.recipient receives the agreed upon amount of tokens
        uint256 outputTokenBalanceAfter = IERC20(payload.toToken).balanceOf(
            payload.recipient
        );
        uint256 balanceDelta = outputTokenBalanceAfter -
            outputTokenBalanceBefore;
        require(balanceDelta >= payload.toAmount, "Order not filled");
        filledAmount[orderUid] = balanceDelta;

        /// @notice Step 6. Execute optional contract post-swap hooks
        /// @dev These are signer authenticated post-swap hooks. These hooks
        /// happen after step 5 because the user may wish to perform an action
        /// (such as deposit into a vault or reinvest/compound) with the swapped funds.
        _execute(signatory, order.payload.hooks.postHooks);

        /// @dev Emit OrderExecuted
        emit OrderExecuted(
            tx.origin,
            msg.sender,
            signatory,
            payload.recipient,
            payload.fromToken,
            payload.toToken,
            payload.fromAmount,
            balanceDelta
        );
    }

    /// @notice Pass hook execution interactions to execution proxy to be executed
    /// @param interactions The interactions to execute
    function _execute(
        address signatory,
        ISettlement.Interaction[] memory interactions
    ) internal {
        if (interactions.length > 0) {
            executionProxy.execute(signatory, interactions);
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
    /// @param order Complete signed order
    /// @return orderUid New order UID
    function _verify(
        ISettlement.Order calldata order
    ) internal returns (bytes memory orderUid) {
        bytes32 digest = buildDigest(order.payload);
        address signatory = SigningLib.recoverSigner(order.signature, digest);
        orderUid = new bytes(OrderLib._UID_LENGTH);
        orderUid.packOrderUidParams(digest, signatory, order.payload.deadline);
        require(filledAmount[orderUid] == 0, "Order already filled");
        require(signatory == order.payload.sender, "Invalid signer");
        require(block.timestamp <= order.payload.deadline, "Deadline expired");
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
/// @dev This is necessary because we cannot allow Settlement to execute arbitrary transaction
/// payloads directly since Settlement may have token approvals.
contract ExecutionProxy {
    address public immutable settlement;

    /// @dev Set settlement address
    constructor() {
        settlement = msg.sender;
    }

    /// @notice Executed user defined interactions signed by sender
    /// @dev Sender has been authenticated by signature recovery
    /// @dev Something very important to consider here is that we are appending
    /// the authenticated sender  (signer) to the end of each interaction calldata.
    /// The reason this is done is to allow the payload signatory to be
    /// authenticated in interaction endpoints. If your interaction endpoint
    /// needs to read signer it can do so by reading the last 20 bytes of calldata.
    /// What this means is that if your interaction endpoint explicitly relies on
    /// calldata length you will need to account for the additional 20 address bytes.
    /// For example: signatory := shr(96, calldataload(sub(calldatasize(), 20)))
    function execute(
        address sender,
        ISettlement.Interaction[] memory interactions
    ) external {
        require(msg.sender == settlement, "Only settlement");
        for (uint256 i; i < interactions.length; i++) {
            ISettlement.Interaction memory interaction = interactions[i];
            (bool success, ) = interaction.target.call{
                value: interaction.value
            }(abi.encodePacked(interaction.callData, sender));
            require(success, "Interaction failed");
        }
    }
}
