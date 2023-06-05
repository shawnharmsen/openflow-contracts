// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;
import {IERC20} from "../../src/interfaces/IERC20.sol";
import {ISettlement} from "../../src/interfaces/ISettlement.sol";
import {SigningLib} from "../../src/lib/Signing.sol";
import {OrderBookNotifier} from "../../src/OrderBookNotifier.sol"; // TODO: IOrderBook
import "forge-std/Test.sol";

contract StrategyProfitEscrowFactory {
    address public settlement;
    uint256 public signatureThreshold;

    // TODO: finish
}

/**
 * @notice This contract is responsible for all signature logic regarding trading profits for want token
 * @dev The only thing this contract can do is take reward from the strategy, sell them, and return profits to strategy
 * @dev The intention is to isolate all profit swapping from the core strategy
 * @dev TODO: More/better comments
 */
contract MultisigAuction {
    // Constants and immutables
    bytes4 private constant _EIP1271_MAGICVALUE = 0x1626ba7e;
    address public immutable factory;
    address public immutable settlement;
    address public immutable orderBookNotifier;

    // Signatures
    uint256 public signatureThresold;
    mapping(address => bool) public signers;
    mapping(bytes32 => bool) public approvedHashes;

    mapping(address => bool) internal _tokenApproved;

    constructor(address _orderBookNotifier, address _settlement) {
        factory = msg.sender;
        orderBookNotifier = _orderBookNotifier;
        settlement = _settlement;
        signatureThresold = 2;
    }

    function initiateSwap(
        address fromToken,
        address toToken,
        uint256 fromAmount,
        uint256 toAmount,
        address recipient,
        ISettlement.Interaction[][2] memory contractInteractions
    ) external {
        if (!_tokenApproved[fromToken]) {
            IERC20(fromToken).approve(settlement, type(uint256).max);
        }

        IERC20(fromToken).transferFrom(msg.sender, address(this), fromAmount); // TODO: SafeTransfer
        ISettlement.Payload memory payload = buildPayload(
            fromToken,
            toToken,
            fromAmount,
            toAmount,
            recipient,
            contractInteractions
        );
        bytes32 digest = ISettlement(settlement).buildDigest(payload);
        approvedHashes[digest] = true;
        OrderBookNotifier(orderBookNotifier).submitOrder(payload);
    }

    function buildPayload(
        address fromToken,
        address toToken,
        uint256 fromAmount,
        uint256 toAmount,
        address recipient,
        ISettlement.Interaction[][2] memory interactions
    ) public returns (ISettlement.Payload memory payload) {
        payload = ISettlement.Payload({
            fromToken: fromToken,
            toToken: toToken,
            fromAmount: fromAmount,
            toAmount: toAmount,
            sender: address(this),
            recipient: recipient,
            nonce: ISettlement(settlement).nonces(address(this)),
            deadline: block.timestamp,
            interactions: interactions
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
        require(approvedHashes[digest], "Digest not approved");
        return _EIP1271_MAGICVALUE;
    }

    // TODO: auth and removing signers
    function addSigners(address[] memory _signers) external {
        for (uint256 signerIdx; signerIdx < _signers.length; signerIdx++) {
            signers[_signers[signerIdx]] = true;
        }
    }
}
