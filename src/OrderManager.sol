// SPDX-License-Identifier: BUSL 1.1

pragma solidity ^0.8.19;
import {IERC20} from "../src/interfaces/IERC20.sol";
import {ISettlement} from "../src/interfaces/ISettlement.sol";
import {OrderLib} from "../src/lib/Order.sol";

/// @author OpenFlow
/// @title Multisig Driver
/// @notice This contract manages the signing logic for OpenFlow multisig authenticated swap auctions.
contract OrderManager {
    /// @dev OrderLib is used to generate and decode unique UIDs per order.
    /// A UID consists of digest hash, owner and deadline.
    using OrderLib for bytes;

    address public immutable defaultOracle;

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

    /// @notice Submit an order.
    /// @dev Given an order payload, build and approve the digest hash, and then emit an event
    /// that indicates an auction is ready to begin.
    /// @param payload The payload to sign.
    /// @return orderUid Returns unique order UID.
    function submitOrder(
        ISettlement.Payload memory payload
    ) external returns (bytes memory orderUid) {
        bytes32 digest = ISettlement(address(this)).buildDigest(payload);
        uint256 sessionNonce = sessionNonceByAddress[msg.sender];
        approvedHashes[msg.sender][sessionNonce][digest] = true;
        orderUid = new bytes(OrderLib._UID_LENGTH);
        orderUid.packOrderUidParams(digest, msg.sender, payload.deadline);
        emit SubmitOrder(payload, orderUid);
    }

    constructor(address _defaultOracle) {
        defaultOracle = _defaultOracle;
    }

    /// @notice Invalidate an order.
    /// @dev Only the user who initiated the order can invalidate the order.
    /// @param orderUid The order UID to invalidate.
    function invalidateOrder(bytes memory orderUid) external {
        (bytes32 digest, address ownerOwner, ) = orderUid
            .extractOrderUidParams();
        uint256 sessionNonce = sessionNonceByAddress[msg.sender];
        approvedHashes[msg.sender][sessionNonce][digest] = false;
        require(msg.sender == ownerOwner, "Only owner of order can invalidate");
        emit InvalidateOrder(orderUid);
    }

    /// @notice Invalidate all orders for a user.
    /// @dev Accomplished by incrementing the user's session nonce.
    function invalidateAllOrders() external {
        sessionNonceByAddress[msg.sender]++;
        emit InvalidateAllOrders(msg.sender);
    }

    /// @notice Determine whether or not a user has approved an order digest for the current session.
    /// @param digest The order digest to check.
    /// @return approved True if approved, false if not.
    function digestApproved(
        address signatory,
        bytes32 digest
    ) external view returns (bool approved) {
        uint256 sessionNonce = sessionNonceByAddress[signatory];
        approved = approvedHashes[signatory][sessionNonce][digest];
    }
}
