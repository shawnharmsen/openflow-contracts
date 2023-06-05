// SPDX-License-Identifier: BUSL 1.1
import "forge-std/Test.sol";

pragma solidity ^0.8.19;
import {IERC20} from "../src/interfaces/IERC20.sol";
import {ISettlement} from "../src/interfaces/ISettlement.sol";
import {SigningLib} from "../src/lib/Signing.sol";
import {OrderLib} from "../src/lib/Order.sol";

/**
 * @notice This contract is responsible for all signature logic regarding trading profits for want token
 * @dev The only thing this contract can do is take reward from the strategy, sell them, and return profits to strategy
 * @dev The intention is to isolate all profit swapping from the core strategy
 * @dev TODO: More/better comments
 */
contract MultisigOrderManager {
    using OrderLib for bytes;
    address public immutable settlement;
    uint256 public signatureThreshold;
    mapping(address => bool) public signers;
    mapping(bytes32 => bool) public approvedHashes;

    event SubmitOrder(ISettlement.Payload payload, bytes orderUid);
    event InvalidateOrder(bytes orderUid);

    constructor(address _settlement) {
        settlement = _settlement;
        signatureThreshold = 2;
    }

    function submitOrder(ISettlement.Payload memory payload) external {
        bytes32 digest = ISettlement(settlement).buildDigest(payload);
        approvedHashes[digest] = true;
        bytes memory orderUid = new bytes(OrderLib._UID_LENGTH);
        orderUid.packOrderUidParams(digest, msg.sender, payload.deadline);
        emit SubmitOrder(payload, orderUid);
    }

    function invalidateOrder(bytes memory orderUid) external {
        (bytes32 digest, address owner, ) = orderUid.extractOrderUidParams();
        approvedHashes[digest] = false;
        require(msg.sender == owner, "Only owner of order can invalidate");
        emit InvalidateOrder(orderUid);
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
