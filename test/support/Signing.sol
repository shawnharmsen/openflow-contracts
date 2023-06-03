// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;
import {IERC20} from "../../src/interfaces/IERC20.sol";
import {ISettlement} from "../../src/interfaces/ISettlement.sol";
import "forge-std/Test.sol";

contract StrategyProfitEscrowFactory {
    address public settlement;
}

// The only thing this contract can do is take reward from the strategy, sell them, and return profits
contract StrategyProfitEscrow {
    // Constants and immutables
    bytes4 private constant _EIP1271_MAGICVALUE = 0x1626ba7e;
    address public immutable factory;
    address public immutable settlement;
    address public immutable strategy;
    address public immutable fromToken; // reward
    address public immutable toToken; // asset

    // Signatures
    mapping(address => bool) public signers;
    mapping(address => mapping(bytes32 => bool)) public approvedHashes;

    constructor(
        address _strategy,
        address _settlement,
        address _fromToken,
        address _toToken
    ) {
        factory = msg.sender;
        strategy = _strategy;
        settlement = _settlement;
        toToken = _toToken;
        fromToken = _fromToken;
        IERC20(fromToken).approve(_settlement, type(uint256).max);
    }

    function addSigners(address[] memory _signers) external {
        for (uint256 signerIdx; signerIdx < _signers.length; signerIdx++) {
            signers[_signers[signerIdx]] = true;
        }
    }

    function isValidSignature(
        bytes32 digest,
        bytes calldata signatures
    ) external view returns (bytes4) {
        uint256 requiredSignatures = 2;
        ISettlement(settlement).checkNSignatures(
            address(this),
            digest,
            signatures,
            requiredSignatures
        );
        return _EIP1271_MAGICVALUE;
    }

    function generatePayload(
        uint256 fromAmount,
        uint256 toAmount
    ) public view returns (ISettlement.Payload memory payload) {
        payload = ISettlement.Payload({
            signingScheme: ISettlement.SigningScheme.Eip1271,
            fromToken: fromToken,
            toToken: toToken,
            fromAmount: fromAmount,
            toAmount: toAmount,
            sender: address(this),
            recipient: strategy,
            nonce: ISettlement(settlement).nonces(address(this)),
            deadline: block.timestamp
        });
    }

    function buildDigest(
        uint256 fromAmount,
        uint256 toAmount
    ) external view returns (bytes32 digest) {
        digest = ISettlement(settlement).buildDigest(
            generatePayload(fromAmount, toAmount)
        );
    }
}
