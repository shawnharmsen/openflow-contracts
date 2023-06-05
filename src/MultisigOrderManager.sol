// SPDX-License-Identifier: BUSL 1.1
import "forge-std/Test.sol";

pragma solidity ^0.8.19;
import {IERC20} from "../src/interfaces/IERC20.sol";
import {ISettlement} from "../src/interfaces/ISettlement.sol";
import {SigningLib} from "../src/lib/Signing.sol";
import {OrderLib} from "../src/lib/Order.sol";

/**
 * @dev TODO: More/better comments
 */
contract MultisigOrderManager {
    using OrderLib for bytes;
    address public immutable settlement;
    uint256 public signatureThreshold;
    mapping(address => bool) public signers;
    mapping(address => mapping(uint256 => mapping(bytes32 => bool)))
        public approvedHashes;
    mapping(address => uint256) public sessionNonceByAddress;

    event SubmitOrder(ISettlement.Payload payload, bytes orderUid);
    event InvalidateOrder(bytes orderUid);
    event InvalidateAllOrders(address account);

    constructor(address _settlement) {
        settlement = _settlement;
        signatureThreshold = 2;
    }

    function submitOrder(
        ISettlement.Payload memory payload
    ) external returns (bytes memory orderUid) {
        bytes32 digest = ISettlement(settlement).buildDigest(payload);
        uint256 sessionNonce = sessionNonceByAddress[msg.sender];
        approvedHashes[msg.sender][sessionNonce][digest] = true;
        bytes memory orderUid = new bytes(OrderLib._UID_LENGTH);
        orderUid.packOrderUidParams(digest, msg.sender, payload.deadline);
        emit SubmitOrder(payload, orderUid);
    }

    function invalidateOrder(bytes memory orderUid) external {
        (bytes32 digest, address owner, ) = orderUid.extractOrderUidParams();
        uint256 sessionNonce = sessionNonceByAddress[msg.sender];
        approvedHashes[msg.sender][sessionNonce][digest] = false;
        require(msg.sender == owner, "Only owner of order can invalidate");
        emit InvalidateOrder(orderUid);
    }

    function invalidateAllOrders() external {
        sessionNonceByAddress[msg.sender]++;
        emit InvalidateAllOrders(msg.sender);
    }

    function digestApproved(bytes32 digest) external view returns (bool) {
        uint256 sessionNonce = sessionNonceByAddress[msg.sender];
        return approvedHashes[msg.sender][sessionNonce][digest];
    }

    function checkNSignatures(
        bytes32 digest,
        bytes memory signatures
    ) external {
        SigningLib.checkNSignatures(
            address(this),
            digest,
            signatures,
            signatureThreshold
        );
    }

    // TODO: Auth and removing signers
    function addSigners(address[] memory _signers) external {
        for (uint256 signerIdx; signerIdx < _signers.length; signerIdx++) {
            signers[_signers[signerIdx]] = true;
        }
    }
}
