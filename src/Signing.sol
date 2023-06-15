// SPDX-License-Identifier: BUSL 1.1
pragma solidity 0.8.19;
import {IMultisigOrderManager} from "./interfaces/IMultisigOrderManager.sol";
import {ISignatureValidator} from "./interfaces/ISignatureValidator.sol";
import {OrderLib} from "./lib/Order.sol";

/// @author OpenFlow
/// @title Signing Library
/// @notice Responsible for all OpenFlow signature logic.
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

    /// @dev Order manager manages the order signature logic for multisig authenticated swap auctions.
    address public immutable orderManager;

    constructor(address _orderManager) {
        orderManager = _orderManager;
    }

    /// @notice Primary signature check endpoint.
    /// @param signature Signature bytes (usually 65 bytes) but in the case of packed
    /// contract signatures actual signature data offset and length may vary.
    /// @param digest Hashed payload digest.
    /// @return owner Returns authenticated owner.
    function recoverSigner(
        bytes32 digest,
        bytes memory signature
    ) public view returns (address owner) {
        /// @dev Extract v from signature
        uint8 v;
        assembly {
            v := and(mload(add(signature, 0x41)), 0xff)
        }
        if (v == 0) {
            /// @dev Contract signature (EIP-1271).
            owner = _recoverEip1271Signer(digest, signature);
        } else if (v == 1) {
            /// @dev Presigned signature requires order manager as signature storage contract.
            owner = _recoverPresignedOwner(digest, signature);
        } else if (v > 30) {
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
        bytes32 r; // owner
        bytes32 s; // signature data offset
        // v is already confirmed to be zero
        assembly {
            r := mload(add(encodedSignature, 0x20))
            s := mload(add(encodedSignature, 0x40))
        }
        /// @dev When handling contract signatures the address of the contract is encoded into r.
        owner = address(uint160(uint256(r)));

        /// @dev Check that signature data pointer (s) is not pointing inside
        /// the static part of the signatures bytes. This check is not completely accurate,
        /// since it is possible that more signatures than the threshold are send.
        // Here we only check that the pointer is not pointing inside the
        /// part that is being processed.
        require(uint256(s) >= 65, "GS021");

        /// @dev Check that signature data pointer (s) is in bounds (points to the length of data -> 32 bytes).
        require(uint256(s) + 32 <= encodedSignature.length, "GS022");

        /// @dev Check if the contract signature is in bounds: start of data is s + 32
        /// and end is start + signature length.
        uint256 contractSignatureLen;
        assembly {
            contractSignatureLen := mload(add(add(encodedSignature, s), 0x20))
        }
        require(
            uint256(s) + 32 + contractSignatureLen <= encodedSignature.length,
            "GS023"
        );

        /// @dev Check signature.
        bytes memory contractSignature;
        assembly {
            /// @dev The signature data for contract signatures is
            /// appended to the concatenated signatures and the offset
            /// is stored in s.
            contractSignature := add(add(encodedSignature, s), 0x20)
        }
        require(
            ISignatureValidator(owner).isValidSignature(
                digest,
                contractSignature
            ) == _EIP1271_MAGICVALUE,
            "GS024"
        );
        return owner;
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
        bytes32 ethsignDigest = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", digest)
        );
        owner = _ecdsaRecover(ethsignDigest, signature);
    }

    /// @notice Verifies the order has been pre-signed. The signature is the
    /// address of the signer of the order.
    /// @param orderDigest The EIP-712 signing digest derived from the order
    /// parameters.
    /// @param encodedSignature The pre-sign signature reprenting the order UID.
    /// @return owner The address of the signer.
    /// TODO: Need validTo?
    function _recoverPresignedOwner(
        bytes32 orderDigest,
        bytes memory encodedSignature
    ) internal view returns (address owner) {
        require(encodedSignature.length == 20, "GPv2: malformed presignature");
        assembly {
            // owner = address(encodedSignature[0:20])
            owner := shr(96, mload(encodedSignature))
        }
        bool presigned = IMultisigOrderManager(orderManager).digestApproved(
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
        (uint8 v, bytes32 r, bytes32 s) = _signatureSplit(signature, 0);
        signer = ecrecover(message, v, r, s);
        require(signer != address(0), "Invalid ECDSA signature");
    }

    /// @notice Splits signature bytes into `uint8 v, bytes32 r, bytes32 s`.
    /// @dev Make sure to perform a bounds check for @param pos, to avoid out of bounds access on @param signatures
    /// The signature format is a compact form of {bytes32 r}{bytes32 s}{uint8 v}
    /// Compact means uint8 is not padded to 32 bytes.
    /// @param pos Which signature to read.
    /// A prior bounds check of this parameter should be performed, to avoid out of bounds access.
    /// @param signatures Concatenated {r, s, v} signatures.
    /// @return v Recovery ID or Safe signature type.
    /// @return r Output value r of the signature.
    /// @return s Output value s of the signature.
    function _signatureSplit(
        bytes memory signatures,
        uint256 pos
    ) internal pure returns (uint8 v, bytes32 r, bytes32 s) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            let signaturePos := mul(0x41, pos)
            r := mload(add(signatures, add(signaturePos, 0x20)))
            s := mload(add(signatures, add(signaturePos, 0x40)))
            /// @dev Here we are loading the last 32 bytes, including 31 bytes of 's'.
            /// There is no 'mload8' to do this. 'byte' is not working due to
            /// the Solidity parser, so lets use the second best option, 'and'.
            v := and(mload(add(signatures, add(signaturePos, 0x41))), 0xff)
        }
    }

    /// @notice Gnosis style signature threshold check.
    /// @dev Since the EIP-1271 does an external call, be mindful of reentrancy attacks.
    /// @dev Reverts if signature threshold is not passed.
    /// @dev Signatures must be packed such that the decimal values of the derived signers are in
    /// ascending numerical order.
    /// For instance `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48` > `0x6B175474E89094C44Da98b954EedeAC495271d0F`,
    /// so the signature for `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48` must come first.
    /// @dev Code comes from Gnosis Safe: https://github.com/safe-global/safe-contracts/blob/main/contracts/Safe.sol
    /// The only change is that we use `recoverSigner()` to calculate signer based on v instead of
    /// doing this inline. The reason for this is that it lets us recover one signer at a time or
    /// multiple signers at a time with maximum  with maximum flexibility.
    /// @param digest The EIP-712 signing digest derived from the order parameters.
    /// @param signatures Packed and encoded multisig signatures payload.
    /// @param requiredSignatures Signature threshold. This is required since we are unable.
    /// to easily determine the number of signatures from the signature payload alone.
    function checkNSignatures(
        bytes32 digest,
        bytes memory signatures,
        uint256 requiredSignatures
    ) public view {
        /// @dev Check that the provided signature data is not too short
        require(signatures.length >= requiredSignatures * 65, "GS020");

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
            (v, r, s) = _signatureSplit(signatures, signatureIdx);
            bytes memory signature = abi.encodePacked(r, s, v);
            currentOwner = recoverSigner(digest, signature);
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
