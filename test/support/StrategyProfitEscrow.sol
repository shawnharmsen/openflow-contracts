// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;
import {IERC20} from "../../src/interfaces/IERC20.sol";
import {ISettlement} from "../../src/interfaces/ISettlement.sol";
import {SigningLib} from "../../src/lib/Signing.sol";
import {Strategy} from "../../test/support/Strategy.sol";
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
contract StrategyProfitEscrow {
    // Constants and immutables
    bytes4 private constant _EIP1271_MAGICVALUE = 0x1626ba7e;
    address public immutable factory;
    address public immutable settlement;
    address public immutable orderBookNotifier;
    address public immutable strategy;
    address public immutable fromToken; // reward
    address public immutable toToken; // asset

    // Signatures
    uint256 public signatureThresold;
    mapping(address => bool) public signers;
    mapping(bytes32 => bool) public approvedHashes;

    constructor(
        address _orderBookNotifier,
        address _strategy,
        address _settlement,
        address _fromToken,
        address _toToken
    ) {
        factory = msg.sender;
        strategy = _strategy;
        orderBookNotifier = _orderBookNotifier;
        settlement = _settlement;
        toToken = _toToken;
        fromToken = _fromToken;
        signatureThresold = 2; // TODO: get from factory
        IERC20(fromToken).approve(_settlement, type(uint256).max);
    }

    // This should call out to the generic solution for swapping tokens in auction form from a contract
    // Maybe call to registry, etc.. WIP
    function initiateSwap(
        ISettlement.Interaction[][2] memory contractInteractions
    ) external {
        uint256 fromAmount = IERC20(fromToken).balanceOf(msg.sender);

        IERC20(fromToken).transferFrom(msg.sender, address(this), fromAmount); // TODO: SafeTransfer
        uint256 toAmount = 100; // TODO: Build min amount
        ISettlement.Payload memory payload = buildPayload(
            fromAmount,
            toAmount,
            contractInteractions
        );
        bytes32 digest = ISettlement(settlement).buildDigest(payload);
        approvedHashes[digest] = true;

        OrderBookNotifier(orderBookNotifier).submitOrder(payload);
    }

    // TODO: Allow canceling a single order, requires thinking about nonces
    function cancelOrders() external {
        // TODO: Canceling order and notifying should be atomic
        ISettlement(settlement).cancelOrders();
        OrderBookNotifier(orderBookNotifier).cancelOrders();
    }

    function buildPayload(
        uint256 fromAmount,
        uint256 toAmount,
        ISettlement.Interaction[][2] memory interactions
    ) public returns (ISettlement.Payload memory payload) {
        payload = ISettlement.Payload({
            fromToken: fromToken,
            toToken: toToken,
            fromAmount: fromAmount,
            toAmount: toAmount,
            sender: address(this),
            recipient: address(strategy),
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
