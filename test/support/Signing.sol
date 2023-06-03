// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;
import {IERC20} from "../../src/interfaces/IERC20.sol";
import {ISettlement} from "../../src/interfaces/ISettlement.sol";
import "forge-std/Test.sol";

// The only thing this contract can do is take reward from the strategy, sell them, and return profits
contract StrategyProfitEscrow {
    bytes4 private constant _EIP1271_MAGICVALUE = 0x1626ba7e;
    ISettlement public settlement; // TODO: Get from factory
    mapping(address => bool) public signers;

    IERC20 fromToken; // reward
    IERC20 toToken; // asset
    address strategy;

    constructor(
        address _strategy,
        address _settlement,
        address _fromToken,
        address _toToken
    ) {
        strategy = _strategy;
        settlement = ISettlement(_settlement);
        toToken = IERC20(_toToken);
        fromToken = IERC20(_fromToken);
        fromToken.approve(_settlement, type(uint256).max);
    }

    function addSigners(address[] memory _signers) external {
        for (uint256 signerIdx; signerIdx < _signers.length; signerIdx++) {
            signers[_signers[signerIdx]] = true;
        }
    }

    function checkNSignatures(
        bytes32 digest,
        bytes memory signatures,
        uint256 requiredSignatures
    ) public view {
        require(
            signatures.length >= requiredSignatures * 65,
            "Invalid signature length"
        );
        address lastOwner;
        address currentOwner;
        for (uint256 i = 0; i < requiredSignatures; i++) {
            bytes memory signature;
            assembly {
                let signaturePos := add(sub(signatures, 28), mul(0x41, i))
                mstore(signature, 65)
                calldatacopy(add(signature, 0x20), signaturePos, 65)
            }
            currentOwner = settlement.recoverSigner(
                ISettlement.SigningScheme.Eip712,
                signature,
                digest
            );
            require(
                currentOwner > lastOwner && signers[currentOwner],
                "Invalid signature order"
            );
            lastOwner = currentOwner;
        }
    }

    function checkNSignaturesCalldata(
        bytes32 digest,
        bytes calldata signatures,
        uint256 requiredSignatures
    ) public view {
        require(
            signatures.length >= requiredSignatures * 65,
            "Invalid signature length"
        );
        address lastOwner;
        address currentOwner;

        for (uint256 i = 0; i < requiredSignatures; i++) {
            bytes memory signature;
            assembly {
                mstore(0x40, add(mload(0x40), 65))
                mstore(signature, 65)
                calldatacopy(
                    add(signature, 0x20),
                    add(add(4, 0x80), mul(mload(i), 65)),
                    65
                )
            }
            currentOwner = settlement.recoverSigner(
                ISettlement.SigningScheme.Eip712,
                signature,
                digest
            );
            require(
                currentOwner > lastOwner && signers[currentOwner],
                "Invalid signature order"
            );
            lastOwner = currentOwner;
        }
    }

    function isValidSignature(
        bytes32 digest,
        bytes calldata signatures
    ) external view returns (bytes4) {
        uint256 requiredSignatures = 2;
        checkNSignaturesCalldata(digest, signatures, requiredSignatures);
        return _EIP1271_MAGICVALUE;
    }

    function generatePayload(
        uint256 fromAmount,
        uint256 toAmount
    ) public view returns (ISettlement.Payload memory payload) {
        payload = ISettlement.Payload({
            signingScheme: ISettlement.SigningScheme.Eip1271,
            fromToken: address(fromToken),
            toToken: address(toToken),
            fromAmount: fromAmount,
            toAmount: toAmount,
            sender: address(this),
            recipient: strategy,
            nonce: settlement.nonces(address(this)),
            deadline: block.timestamp
        });
    }

    function buildDigest(
        uint256 fromAmount,
        uint256 toAmount
    ) external view returns (bytes32 digest) {
        digest = settlement.buildDigest(generatePayload(fromAmount, toAmount));
    }
}
