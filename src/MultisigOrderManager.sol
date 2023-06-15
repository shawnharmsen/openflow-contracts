// SPDX-License-Identifier: BUSL 1.1

pragma solidity ^0.8.19;
import {IERC20} from "../src/interfaces/IERC20.sol";
import {ISettlement} from "../src/interfaces/ISettlement.sol";
import {OrderLib} from "../src/lib/Order.sol";
import {SigningLib} from "../src/lib/Signing.sol";

/// @author OpenFlow
/// @title Multisig Order Manager
/// @notice This contract manages the signing logic for OpenFlow multisig authenticated swap auctions
contract MultisigOrderManager {
    /// @dev OrderLib is used to generate and decode unique UIDs per order.
    /// A UID consists of digest hash, owner and deadline.
    using OrderLib for bytes;

    /// @dev Settlement contract is used to build a digest hash given a payload.
    address public settlement;

    /// @dev Owner is responsible for signer management (adding/removing signers
    /// and maintaining signature threshold).
    address public owner;

    /// @dev In order for a multisig authenticated order to be executed the order
    /// must be signed by `signatureThreshold` trusted parties. This ensures that the
    /// optimal quote has been selected for a given auction. The main trust component here in multisig
    /// authenticated auctions is that the user is trusting the multisig to only sign quotes that will return
    /// the highest swap value to the end user.
    uint256 public signatureThreshold;

    /// @dev Signers is mapping of authenticated multisig signers.
    mapping(address => bool) public signers;

    /// @dev approvedHashes[owner][nonce][hash]
    /// Allows a user to validate and invalidate an order.
    mapping(address => mapping(uint256 => mapping(bytes32 => bool)))
        public approvedHashes;

    /// @dev All orders for a user can be invalidated by incrementing the user's session nonce.
    mapping(address => uint256) public sessionNonceByAddress;

    /// @dev Event emitted when an order is submitted. This event is used off-chain to detect new orders.
    /// When a SubmitOrder event is fired, multisig auction authenticators (signers) will request new quotes from all
    /// solvers, and when the auction period is up, multisig will sign the best quote. The signature will be relayed to
    /// the solver who submitted the quote. When the solver has enough multisig signatures, the solver can construct
    /// the multisig signature (see: https://docs.safe.global/learn/safe-core/safe-core-protocol/signatures) and
    /// execute the order.
    event SubmitOrder(ISettlement.Payload payload, bytes orderUid);

    /// @dev Event emitted when an order is invalidated. Only users who submit an order can invalidate the order.
    /// When an order is invalidated it is no longer able to be executed.
    event InvalidateOrder(bytes orderUid);

    /// @dev Event emitted to indicate a user has invalidated all of their orders. This is accomplished by the
    /// user incrementing their session nonce.
    event InvalidateAllOrders(address account);

    constructor() {
        owner = msg.sender; // Initialize owner
    }

    /// @notice Submit an order
    /// @dev Given an order payload, build and approve the digest hash, and then emit an event
    /// that indicates an auction is ready to begin.
    /// @param payload The payload to sign
    /// @return orderUid Returns unique order UID
    function submitOrder(
        ISettlement.Payload memory payload
    ) external returns (bytes memory orderUid) {
        bytes32 digest = ISettlement(settlement).buildDigest(payload);
        uint256 sessionNonce = sessionNonceByAddress[msg.sender];
        approvedHashes[msg.sender][sessionNonce][digest] = true;
        orderUid = new bytes(OrderLib._UID_LENGTH);
        orderUid.packOrderUidParams(digest, msg.sender, payload.deadline);
        emit SubmitOrder(payload, orderUid);
    }

    /// @notice Invalidate an order
    /// @dev Only the user who initiated the order can invalidate the order
    /// @param orderUid The order UID to invalidate
    function invalidateOrder(bytes memory orderUid) external {
        (bytes32 digest, address ownerOwner, ) = orderUid
            .extractOrderUidParams();
        uint256 sessionNonce = sessionNonceByAddress[msg.sender];
        approvedHashes[msg.sender][sessionNonce][digest] = false;
        require(msg.sender == ownerOwner, "Only owner of order can invalidate");
        emit InvalidateOrder(orderUid);
    }

    /// @notice Invalidate all orders for a user
    /// @dev Accomplished by incrementing the user's session nonce
    function invalidateAllOrders() external {
        sessionNonceByAddress[msg.sender]++;
        emit InvalidateAllOrders(msg.sender);
    }

    /// @notice Determine whether or not a user has approved an order digest for the current session
    /// @param digest The order digest to check
    /// @return approved True if approved, false if not
    function digestApproved(
        address signatory,
        bytes32 digest
    ) external view returns (bool approved) {
        uint256 sessionNonce = sessionNonceByAddress[signatory];
        approved = approvedHashes[signatory][sessionNonce][digest];
    }

    /// @notice Given a digest and encoded signatures, determine if a digest is approved by a
    /// sufficient number of multisig signers.
    /// @dev Reverts if not approved
    function checkNSignatures(
        bytes32 digest,
        bytes memory signatures
    ) external view {
        SigningLib.checkNSignatures(
            address(this),
            digest,
            signatures,
            signatureThreshold
        );
    }

    /// @notice Add or remove trusted multisig signers
    /// @dev Only owner is allowed to perform this action
    /// @param _signers An array of signer addresses
    /// @param _status If true, all signers in the array will be approved.
    /// If false all signers in the array will be unapproved.
    function setSigners(address[] memory _signers, bool _status) external {
        require(msg.sender == owner, "Only owner");
        for (uint256 signerIdx; signerIdx < _signers.length; signerIdx++) {
            signers[_signers[signerIdx]] = _status;
        }
    }

    /// @notice Set signature threshold
    /// @dev Only owner is allowed to perform this action
    function setSignatureThreshold(uint256 _signatureThreshold) external {
        require(msg.sender == owner, "Only owner");
        signatureThreshold = _signatureThreshold;
    }

    /// @notice Select a new owner
    /// @dev Only owner is allowed to perform this action
    function setOwner(address _owner) external {
        require(msg.sender == owner, "Only owner");
        owner = _owner;
    }

    /// @notice Initialize order manager
    /// @dev Sets settlement
    /// @dev Can only initialize once
    /// @param _settlement New settlement address
    function initialize(address _settlement) external {
        require(settlement == address(0));
        settlement = _settlement;
    }
}
