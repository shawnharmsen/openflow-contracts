// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;
import {IERC20} from "../../src/interfaces/IERC20.sol";
import {ISettlement} from "../../src/interfaces/ISettlement.sol";
import {SigningLib} from "../../src/lib/Signing.sol";
import "forge-std/Test.sol";

contract StrategyProfitEscrowFactory {
    address public settlement;

    // TODO: finish
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
    uint256 public requiredSignatures;
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
        requiredSignatures = 2; // TODO: support updating this
        IERC20(fromToken).approve(_settlement, type(uint256).max);
    }

    function isValidSignature(
        bytes32 digest,
        bytes calldata signatures
    ) external view returns (bytes4) {
        SigningLib.checkNSignatures(
            address(this),
            digest,
            signatures,
            requiredSignatures
        );
        return _EIP1271_MAGICVALUE;
    }

    // TODO: auth and removing signers
    function addSigners(address[] memory _signers) external {
        for (uint256 signerIdx; signerIdx < _signers.length; signerIdx++) {
            signers[_signers[signerIdx]] = true;
        }
    }
}
