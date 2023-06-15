// SPDX-License-Identifier: BUSL 1.1
pragma solidity 0.8.19;
import {IMultisigOrderManager} from "../interfaces/IMultisigOrderManager.sol";
import {ISignatureValidator} from "../interfaces/ISignatureValidator.sol";
import {OrderLib} from "./Order.sol";

/// @author OpenFlow
/// @title Signing Library
/// @notice Responsible for all OpenFlow signature logic
/// @dev This library is a slightly modified combined version of two battle
/// signing libraries (Gnosis Safe and Cowswap). The intention here is to make an
/// extremely versatile signing lib to handle all major signature types as well as
/// multisig signatures. It handles EIP-712, EIP-1271, EthSign and Gnosis style
/// multisig signature threshold. Multisig signatures can be comprised of any
/// combination of signature types. Signature type is auto-detected (per Gnosis)
/// based on v value.
library SigningLib {
    uint256 private constant _ECDSA_SIGNATURE_LENGTH = 65;
    bytes4 private constant _EIP1271_MAGICVALUE = 0x1626ba7e;

    /// @notice Primary signature check endpoint
    /// @param signature Signature bytes (usually 65 bytes) but in the case of packed
    /// contract signatures actual signature data offset and length may vary
    /// @param digest Hashed payload digest
    /// @return owner Returns authenticated owner
    function recoverSigner(
        bytes memory signature,
        bytes32 digest
    ) public view returns (address owner) {
        /// @dev Extract v from signature
        uint8 v;
        assembly {
            v := and(mload(add(signature, 0x41)), 0xff)
        }
        if (v == 0) {
            /// @dev Contract signature (EIP-1271)
            owner = recoverEip1271Signer(digest, signature);
        } else if (v == 1) {
            /// @dev Presigned signature requires order manager as signature storage contract
            owner = recoverPresignedOwner(digest, signature);
        } else if (v > 30) {
            /// @dev EthSign signature. If v > 30 then default va (27,28)
            /// has been adjusted for eth_sign flow
            owner = recoverEthsignSigner(digest, signature);
        } else {
            /// @dev EIP-712 signature. Default is the ecrecover flow with the provided data hash
            owner = recoverEip712Signer(digest, signature);
        }
    }

    /// @notice Recover EIP 712 signer
    /// @param digest Hashed payload digest
    /// @param signature Signature bytes
    /// @return owner Signature owner
    function recoverEip712Signer(
        bytes32 digest,
        bytes memory signature
    ) internal pure returns (address owner) {
        owner = ecdsaRecover(digest, signature);
    }

    /// @notice Extract forward and validate signature for EIP-1271
    /// @dev See "Contract Signature" section of https://docs.safe.global/learn/safe-core/safe-core-protocol/signatures
    /// @param digest Hashed payload digest
    /// @param encodedSignature Encoded signature
    /// @return owner Signature owner
    function recoverEip1271Signer(
        bytes32 digest,
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
            ISignatureValidator(owner).isValidSignature(digest, signature) ==
                _EIP1271_MAGICVALUE,
            "Invalid EIP-1271 signature"
        );
        return owner;
    }

    /// @notice Eth sign signature
    /// @dev Uses ecdsaRecover with "Ethereum Signed Message" prefixed
    /// @param digest Hashed payload digest
    /// @param signature Signature
    /// @return owner Signature owner
    function recoverEthsignSigner(
        bytes32 digest,
        bytes memory signature
    ) internal pure returns (address owner) {
        bytes32 ethsignDigest = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", digest)
        );
        owner = ecdsaRecover(ethsignDigest, signature);
    }

    /// @notice Verifies the order has been pre-signed. The signature is the
    /// address of the signer of the order.
    /// @param orderDigest The EIP-712 signing digest derived from the order
    /// parameters.
    /// @param encodedSignature The pre-sign signature reprenting the order UID.
    /// @return owner The address of the signer.
    /// TODO: Need validTo?
    function recoverPresignedOwner(
        bytes32 orderDigest,
        bytes memory encodedSignature
    ) internal view returns (address owner) {
        require(encodedSignature.length == 20, "GPv2: malformed presignature");
        assembly {
            // owner = address(encodedSignature[0:20])
            owner := shr(96, mload(encodedSignature))
        }
        // bool presigned = IMultisigOrderManager(orderManager).digestApproved(
        //     owner,
        //     orderDigest
        // );
        // require(presigned, "Order not presigned");
    }

    /// @notice Utility for recovering signature using ecrecover
    /// @dev Signature length is expected to be exactly 65 bytes
    /// @param message Signed messed
    /// @param signature Signature
    /// @return signer Returns signer (signature owner)
    function ecdsaRecover(
        bytes32 message,
        bytes memory signature
    ) internal pure returns (address signer) {
        require(
            signature.length == _ECDSA_SIGNATURE_LENGTH,
            "Malformed ECDSA signature"
        );
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := and(mload(add(signature, 0x41)), 0xff)
        }
        signer = ecrecover(message, v, r, s);
        require(signer != address(0), "Invalid ECDSA signature");
    }

    /// @notice Gnosis style signature threshold check
    /// @param orderManager The address responsible for signer storage and order management
    /// @param digest The digest to check signatures for
    /// @param signatures Packed and encoded multisig signatures payload
    /// @param requiredSignatures Signature threshold. This is required since we are unable
    /// to easily determine the number of signatures from the signature payload alone
    /// @dev Reverts if signature threshold is not passed
    function checkNSignatures(
        address orderManager,
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
                IMultisigOrderManager(orderManager).signers(currentOwner),
                "Signer is not approved"
            );
            lastOwner = currentOwner;
        }
    }
}
