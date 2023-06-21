// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;
import {ISettlement} from "./interfaces/ISettlement.sol";
import {ISignatureValidator} from "./interfaces/ISignatureValidator.sol";
import {ISettlement} from "./interfaces/ISettlement.sol";
import {IDriver} from "./interfaces/IDriver.sol";

/// @author Openflow
/// @title Signing Library
/// @notice Responsible for all Openflow signature logic.
/// @dev This library is a slightly modified combined version of two battle
/// signing libraries (Gnosis Safe and Cowswap). The intention here is to make an
/// extremely versatile signing lib to handle all major signature types as well as
/// multisig signatures. It handles EIP-712, EIP-1271, EthSign, Presign and Gnosis style
/// multisig signature threshold. Multisig signatures can be comprised of any
/// combination of signature types. Signature type is auto-detected (per Gnosis)
/// based on v value.
contract Signing {
    /// @dev All ECDSA signatures (EIP-712 and EthSign) must be 65 bytes.
    /// @dev Contract signatures (EIP-1271) can be any number of bytes, however
    /// Gnosis-style threshold packed signatures must adhere to the Gnosis contract.
    /// Signature format: {32-bytes owner_1 (r)}{32-bytes signature_offset_1 (s)}{1-byte v_1 (0)}{signature_length_1}{signature_bytes_1}
    uint256 private constant _ECDSA_SIGNATURE_LENGTH = 65;
    bytes4 private constant _EIP1271_MAGICVALUE = 0x1626ba7e;
    address public immutable defaultDriver;

    /// TODO: comments
    constructor(address _defaultDriver) {
        defaultDriver = _defaultDriver;
    }

    /// @notice Primary signature check endpoint.
    /// @param signature Signature bytes (usually 65 bytes) but in the case of packed
    /// contract signatures actual signature data offset and length may vary.
    /// @param digest Hashed payload digest.
    /// @return owner Returns authenticated owner.
    function recoverSigner(
        ISettlement.Scheme scheme,
        bytes32 digest,
        bytes memory signature
    ) public view returns (address owner) {
        /// @dev Extract v from signature
        if (scheme == ISettlement.Scheme.Eip1271) {
            /// @dev Contract signature (EIP-1271).
            owner = _recoverEip1271Signer(digest, signature);
        } else if (scheme == ISettlement.Scheme.PreSign) {
            /// @dev Presigned signature requires order manager as signature storage contract.
            owner = _recoverPresignedOwner(digest, signature);
        } else if (scheme == ISettlement.Scheme.EthSign) {
            /// @dev EthSign signature. If v > 30 then default va (27,28)
            /// has been adjusted for eth_sign flow.
            owner = _recoverEthSignSigner(digest, signature);
        } else {
            /// @dev EIP-712 signature. Default is the ecrecover flow with the provided data hash.
            owner = _recoverEip712Signer(digest, signature);
        }
    }

    /// @notice Recover EIP 712 signer.
    /// @param digest Hashed payload digest.
    /// @param signature Signature bytes.
    /// @return owner Signature owner.
    function _recoverEip712Signer(
        bytes32 digest,
        bytes memory signature
    ) internal pure returns (address owner) {
        owner = _ecdsaRecover(digest, signature);
    }

    /// @notice Extract forward and validate signature for EIP-1271.
    /// @dev See "Contract Signature" section of https://docs.safe.global/learn/safe-core/safe-core-protocol/signatures
    /// @dev Code comes from Gnosis Safe: https://github.com/safe-global/safe-contracts/blob/main/contracts/Safe.sol
    /// @param digest Hashed payload digest.
    /// @param encodedSignature Encoded signature.
    /// @return owner Signature owner.
    function _recoverEip1271Signer(
        bytes32 digest,
        bytes memory encodedSignature
    ) internal view returns (address owner) {
        bytes memory signature;
        uint256 signatureLength = encodedSignature.length - 20;
        assembly {
            owner := mload(add(encodedSignature, 20))
            mstore(add(encodedSignature, 20), signatureLength)
            signature := add(encodedSignature, 20)
        }
        require(
            ISignatureValidator(owner).isValidSignature(digest, signature) ==
                _EIP1271_MAGICVALUE,
            "EIP-1271 signature is invalid"
        );
    }

    /// @notice Recover signature using eth sign.
    /// @dev Uses ecdsaRecover with "Ethereum Signed Message" prefixed.
    /// @param digest Hashed payload digest.
    /// @param signature Signature.
    /// @return owner Signature owner.
    function _recoverEthSignSigner(
        bytes32 digest,
        bytes memory signature
    ) internal pure returns (address owner) {
        // The signed message is encoded as:
        // `"\x19Ethereum Signed Message:\n" || length || data`, where
        // the length is a constant (32 bytes) and the data is defined as:
        // `orderDigest`.
        bytes32 ethSignDigest = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", digest)
        );
        owner = _ecdsaRecover(ethSignDigest, signature);
    }

    /// @notice Verifies the order has been pre-signed. The signature is the
    /// address of the signer of the order.
    /// @param orderDigest The EIP-712 signing digest derived from the order
    /// parameters.
    /// @param encodedSignature The pre-sign signature reprenting the order UID.
    /// @return owner The address of the signer.
    function _recoverPresignedOwner(
        bytes32 orderDigest,
        bytes memory encodedSignature
    ) internal view returns (address owner) {
        require(encodedSignature.length == 20, "Malformed presignature");
        assembly {
            // owner = address(encodedSignature[0:20])
            owner := shr(96, mload(add(encodedSignature, 0x20)))
        }
        bool presigned = ISettlement(address(this)).digestApproved(
            owner,
            orderDigest
        );
        require(presigned, "Order not presigned");
    }

    /// @notice Utility for recovering signature using ecrecover.
    /// @dev Signature length is expected to be exactly 65 bytes.
    /// @param message Signed messed.
    /// @param signature Signature.
    /// @return signer Returns signer (signature owner).
    function _ecdsaRecover(
        bytes32 message,
        bytes memory signature
    ) internal pure returns (address signer) {
        require(
            signature.length == _ECDSA_SIGNATURE_LENGTH,
            "Malformed ECDSA signature"
        );
        (bytes32 r, bytes32 s) = abi.decode(signature, (bytes32, bytes32));
        uint8 v = uint8(signature[64]);

        signer = ecrecover(message, v, r, s);
        require(signer != address(0), "Invalid ECDSA signature");
    }

    /// @notice Gnosis style signature threshold check.
    /// @dev Since the EIP-1271 does an external call, be mindful of reentrancy attacks.
    /// @dev Reverts if signature threshold is not passed.
    /// @dev Signatures must be packed such that the decimal values of the derived signers are in
    /// ascending numerical order.
    /// For instance `0xA0b8...eB48` > `0x6B17....71d0F`, so the signature for `0xA0b8...eB48` must come first.
    /// @dev Code comes from Gnosis Safe: https://github.com/safe-global/safe-contracts/blob/main/contracts/Safe.sol
    /// @dev Use `recoverSigner()` methods wherever possible and use exact Gnosis code when v == 0 (contract signatures)
    /// @param digest The EIP-712 signing digest derived from the order parameters.
    /// @param signatures Packed and encoded multisig signatures payload.
    /// @param requiredSignatures Signature threshold. This is required since we are unable.
    /// to easily determine the number of signatures from the signature payload alone.
    function checkNSignatures(
        address driver,
        bytes32 digest,
        bytes memory signatures,
        uint256 requiredSignatures
    ) public view {
        /// @dev Check that the provided signature data is not too short
        require(
            signatures.length >= requiredSignatures * 65,
            "Not enough signatures provided"
        );

        /// @dev There cannot be an owner with address 0.
        address lastOwner = address(0);
        address currentOwner;
        uint256 signatureIdx;
        bytes32 r;
        bytes32 s;
        uint8 v;
        for (
            signatureIdx = 0;
            signatureIdx < requiredSignatures;
            signatureIdx++
        ) {
            // From Gnosis `signatureSplit` method
            assembly {
                let signaturePos := mul(0x41, signatureIdx)
                r := mload(add(signatures, add(signaturePos, 0x20)))
                s := mload(add(signatures, add(signaturePos, 0x40)))
                v := and(mload(add(signatures, add(signaturePos, 0x41))), 0xff)
            }
            bytes memory signature = abi.encodePacked(r, s, v);
            if (v == 0) {
                /// @dev When handling contract signatures the address of the contract is encoded into r.
                currentOwner = address(uint160(uint256(r)));

                /// @dev Check that signature data pointer (s) is not pointing inside
                /// the static part of the signatures bytes. This check is not completely accurate,
                /// since it is possible that more signatures than the threshold are send.
                // Here we only check that the pointer is not pointing inside the
                /// part that is being processed.
                require(uint256(s) >= 65, "Signature data pointer is invalid");

                /// @dev Check that signature data pointer (s) is in bounds (points to the length of data -> 32 bytes).
                require(
                    uint256(s) + 32 <= signature.length,
                    "Signature data pointer is out of bounds"
                );

                /// @dev Check if the contract signature is in bounds: start of data is s + 32
                /// and end is start + signature length.
                uint256 contractSignatureLen;
                assembly {
                    contractSignatureLen := mload(add(add(signature, s), 0x20))
                }
                require(
                    uint256(s) + 32 + contractSignatureLen <= signature.length,
                    "Signature is out of bounds"
                );

                /// @dev Check signature.
                bytes memory contractSignature;
                assembly {
                    /// @dev The signature data for contract signatures is
                    /// appended to the concatenated signatures and the offset
                    /// is stored in s.
                    contractSignature := add(add(signature, s), 0x20)
                }

                /// @dev Perform signature validation on the contract here rather than using
                /// `_recoverEip1271Signer()` to save gas since we already have all the data
                /// here and the call is simple.
                /// @dev currentOwner (r) is set above
                require(
                    ISignatureValidator(currentOwner).isValidSignature(
                        digest,
                        contractSignature
                    ) == _EIP1271_MAGICVALUE,
                    "EIP-1271 signature is invalid"
                );
            } else if (v == 1) {
                /// @dev Presigned signature requires order manager as signature storage contract.
                currentOwner = _recoverPresignedOwner(
                    digest,
                    abi.encodePacked(address(uint160(uint256(r))))
                );
            } else if (v > 30) {
                /// @dev EthSign signature. If v > 30 then default va (27,28)
                /// has been adjusted for eth_sign flow.
                uint8 adjustedV = v - 4;
                signature = abi.encodePacked(r, s, adjustedV);
                currentOwner = _recoverEthSignSigner(digest, signature);
            } else {
                /// @dev Default to EDCSA ecrecover flow with the provided data hash.
                currentOwner = _recoverEip712Signer(digest, signature);
            }

            require(
                currentOwner > lastOwner,
                "Invalid signature order or duplicate signature"
            );
            require(
                IDriver(driver).signers(currentOwner),
                "Signer is not approved"
            );
            lastOwner = currentOwner;
        }
    }
}
