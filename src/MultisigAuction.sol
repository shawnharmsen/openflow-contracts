// SPDX-License-Identifier: BUSL 1.1
import "forge-std/Test.sol";

pragma solidity ^0.8.19;
import {IERC20} from "../src/interfaces/IERC20.sol";
import {ISettlement} from "../src/interfaces/ISettlement.sol";
import {SigningLib} from "../src/lib/Signing.sol";
import {OrderLib} from "../src/lib/Order.sol";

interface IMultisigAuction {
    struct SwapOrder {
        address fromToken;
        address toToken;
        uint256 amountIn;
        uint256 minAmountOut;
        address recipient;
        ISettlement.Hooks hooks;
    }
}

/**
 * @notice This contract is responsible for all signature logic regarding trading profits for want token
 * @dev The only thing this contract can do is take reward from the strategy, sell them, and return profits to strategy
 * @dev The intention is to isolate all profit swapping from the core strategy
 * @dev TODO: More/better comments
 */
contract MultisigAuction {
    using OrderLib for bytes;
    bytes4 private constant _EIP1271_MAGICVALUE = 0x1626ba7e;
    address public immutable settlement;
    address public immutable orderBookNotifier;
    uint256 public signatureThresold;
    mapping(address => bool) public signers;
    mapping(bytes32 => bool) public approvedHashes;
    mapping(address => bool) internal _tokenApproved;
    mapping(address => mapping(address => uint256))
        public amountStoredByAccountByToken;

    event SubmitOrder(ISettlement.Payload payload, bytes orderUid);
    event InvalidateOrder(bytes orderUid);

    constructor(address _orderBookNotifier, address _settlement) {
        orderBookNotifier = _orderBookNotifier;
        settlement = _settlement;
        signatureThresold = 2;
    }

    function initiateSwap(
        IMultisigAuction.SwapOrder memory swapOrder
    ) external {
        if (!_tokenApproved[swapOrder.fromToken]) {
            IERC20(swapOrder.fromToken).approve(settlement, type(uint256).max);
        }
        IERC20(swapOrder.fromToken).transferFrom(
            msg.sender,
            address(this),
            swapOrder.amountIn
        ); // TODO: SafeTransfer
        ISettlement.Payload memory payload = buildPayload(swapOrder);
        bytes32 digest = ISettlement(settlement).buildDigest(payload);
        approvedHashes[digest] = true;

        bytes memory orderUid = new bytes(OrderLib._UID_LENGTH);
        orderUid.packOrderUidParams(digest, msg.sender, payload.deadline);

        emit SubmitOrder(payload, orderUid);

        amountStoredByAccountByToken[msg.sender][
            swapOrder.fromToken
        ] += swapOrder.amountIn;
    }

    function buildPayload(
        IMultisigAuction.SwapOrder memory swapOrder
    ) public returns (ISettlement.Payload memory payload) {
        payload = ISettlement.Payload({
            fromToken: swapOrder.fromToken,
            toToken: swapOrder.toToken,
            fromAmount: swapOrder.amountIn,
            toAmount: swapOrder.minAmountOut,
            sender: address(this),
            recipient: swapOrder.recipient,
            nonce: ISettlement(settlement).nonces(address(this)),
            deadline: uint32(block.timestamp),
            hooks: swapOrder.hooks
        });
    }

    function isValidSignature(
        bytes32 digest,
        bytes calldata signatures
    ) external view returns (bytes4) {
        SigningLib.checkNSignatures(
            address(this),
            digest,
            signatures,
            signatureThresold
        );
        // TODO: Instead of approvedHashes use UID (includes digest, owner and deadline)
        require(approvedHashes[digest], "Digest not approved");
        return _EIP1271_MAGICVALUE;
    }

    function invalidateOrder(bytes memory orderUid) external {
        (bytes32 digest, address owner, ) = orderUid.extractOrderUidParams();
        approvedHashes[digest] = false;
        require(msg.sender == owner, "Only owner of order can invalidate");
        emit InvalidateOrder(orderUid);
    }

    // TODO: Auth and removing signers
    function addSigners(address[] memory _signers) external {
        for (uint256 signerIdx; signerIdx < _signers.length; signerIdx++) {
            signers[_signers[signerIdx]] = true;
        }
    }
}
