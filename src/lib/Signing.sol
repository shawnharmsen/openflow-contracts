// SPDX-License-Identifier: BUSL 1.1
pragma solidity 0.8.19;
import "../interfaces/ISettlement.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/IEip1271SignatureValidator.sol";
import "../interfaces/ISignatureManager.sol";

interface ISignatureValidator {
    function isValidSignature(
        bytes32,
        bytes memory
    ) external view returns (bytes4);
}

library SigningLib {
    uint256 private constant _ECDSA_SIGNATURE_LENGTH = 65;
    bytes4 private constant _EIP1271_MAGICVALUE = 0x1626ba7e;

    function recoverSigner(
        bytes memory signature,
        bytes32 digest
    ) public view returns (address owner) {
        uint8 v;
        assembly {
            v := and(mload(add(signature, 0x41)), 0xff)
        }
        if (v == 0) {
            // Contract signature
            owner = recoverEip1271Signer(digest, signature);
        } else if (v == 1) {
            // currentOwner = recoverPresignedOwner(digest, signature);
        } else if (v > 30) {
            // If v > 30 then default va (27,28) has been adjusted for eth_sign flow
            owner = recoverEthsignSigner(digest, signature);
        } else {
            // Default is the ecrecover flow with the provided data hash
            owner = recoverEip712Signer(digest, signature);
        }
    }

    function recoverEip712Signer(
        bytes32 orderDigest,
        bytes memory encodedSignature
    ) internal pure returns (address owner) {
        owner = ecdsaRecover(orderDigest, encodedSignature);
    }

    /**
     * @notice Extract, forward and validate signature for EIP-1271
     * @dev See "Contract Signature" section of https://docs.safe.global/learn/safe-core/safe-core-protocol/signatures
     * @dev It's not actually necessary to read the length byte here
     */
    function recoverEip1271Signer(
        bytes32 orderDigest,
        bytes memory encodedSignature
    ) internal view returns (address owner) {
        bytes32 signatureOffset;
        uint256 signatureLength;
        bytes memory signature;

        assembly {
            owner := mload(add(encodedSignature, 0x20))
            signatureOffset := mload(add(encodedSignature, 0x40))
            signatureLength := mload(add(encodedSignature, 0x80))
            mstore(signature, signatureLength)
            calldatacopy(
                add(signature, 0x20),
                add(add(signature, signatureOffset), 0x24), // digest + free memory + 4byte
                signatureLength
            )
        }
        require(
            IEip1271SignatureValidator(owner).isValidSignature(
                orderDigest,
                signature
            ) == _EIP1271_MAGICVALUE,
            "Invalid EIP-1271 signature"
        );
        return owner;
    }

    function recoverEthsignSigner(
        bytes32 orderDigest,
        bytes memory encodedSignature
    ) internal pure returns (address owner) {
        bytes32 ethsignDigest = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", orderDigest)
        );
        owner = ecdsaRecover(ethsignDigest, encodedSignature);
    }

    function ecdsaRecover(
        bytes32 message,
        bytes memory encodedSignature
    ) internal pure returns (address signer) {
        require(
            encodedSignature.length == _ECDSA_SIGNATURE_LENGTH,
            "Malformed ECDSA signature"
        );
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(encodedSignature, 0x20))
            s := mload(add(encodedSignature, 0x40))
            v := and(mload(add(encodedSignature, 0x41)), 0xff)
        }
        signer = ecrecover(message, v, r, s);
        require(signer != address(0), "Invalid ECDSA signature");
    }

    // TODO: Implement
    // function recoverPresignedOwner(
    //     bytes32 digest,
    //     bytes memory signature
    // ) public view returns (address currentOwner) {
    //     // If v is 1 then it is an approved hash
    //     currentOwner = address(uint160(uint256(r)));
    //     require(
    //         msg.sender == currentOwner ||
    //             ISignatureManager(signatureManager).approvedHashes(
    //                 currentOwner,
    //                 digest
    //             ),
    //         "Hash is not approved"
    //     );
    // }

    function checkNSignatures(
        address signatureManager,
        bytes32 digest,
        bytes memory signatures,
        uint256 requiredSignatures
    ) public view {
        require(signatures.length >= requiredSignatures * 65, "GS020");
        address lastOwner = address(0);
        address currentOwner;
        uint256 i;
        for (i = 0; i < requiredSignatures; i++) {
            bytes memory signature;
            // TODO: More checks? Review Gnosis code: https://ftmscan.com/address/d9db270c1b5e3bd161e8c8503c55ceabee709552#code
            assembly {
                // Similar to Gnosis signatureSplit, except splits the entire signature into 65 byte chunks instead of r, s, v
                let signaturePos := add(
                    add(sub(signatures, 28), mul(0x41, i)),
                    0x40
                )
                mstore(signature, 65)
                calldatacopy(add(signature, 0x20), signaturePos, 65)
            }
            currentOwner = recoverSigner(signature, digest);

            require(
                currentOwner > lastOwner,
                "Invalid signature order or duplicate signature"
            );
            require(
                ISignatureManager(signatureManager).signers(currentOwner),
                "Signer is not approved"
            );
            lastOwner = currentOwner;
        }
    }
}
