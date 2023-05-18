// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "../../src/Settlement.sol";

contract SigUtils {
    bytes32 public immutable domainSeparator;
    bytes32 public immutable typeHash;

    constructor(bytes32 _domainSeparator, bytes32 _typeHash) {
        domainSeparator = _domainSeparator;
        typeHash = _typeHash;
    }

    function buildDigest(
        Settlement.Payload memory _payload
    ) public view returns (bytes32 digest) {
        bytes32 structHash = keccak256(
            abi.encode(
                typeHash,
                _payload.signingScheme,
                _payload.fromToken,
                _payload.toToken,
                _payload.fromAmount,
                _payload.toAmount,
                _payload.sender,
                _payload.recipient,
                _payload.nonce,
                _payload.deadline
            )
        );
        digest = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash)
        );
    }
}
