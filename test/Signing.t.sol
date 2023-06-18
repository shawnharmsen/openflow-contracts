// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;
import "./support/Storage.sol";

contract NegativeTestCaseSigningContract {
    function isValidSignature(
        bytes32 digest,
        bytes calldata signatures
    ) external returns (bytes4) {}
}

contract SigningTest is Storage {
    bytes32 digest = bytes32(hex"1337");
    bytes32 badDigest = bytes32(hex"deadbeef");

    function testPresign() external {
        /// @dev Malformed presignature.
        bytes memory encodedSignatures = abi.encodePacked(strategy, hex"00");
        vm.expectRevert("Malformed presignature");
        settlement.recoverSigner(
            ISettlement.Scheme.PreSign,
            digest,
            encodedSignatures
        );

        /// @dev Order not presigned.
        encodedSignatures = abi.encodePacked(strategy);
        vm.expectRevert("Order not presigned");
        settlement.recoverSigner(
            ISettlement.Scheme.PreSign,
            digest,
            encodedSignatures
        );
    }

    function testEip1271() external {
        bytes memory signature1 = _sign(_USER_A_PRIVATE_KEY, digest);
        bytes memory signature2 = _sign(_USER_B_PRIVATE_KEY, digest);
        bytes memory signatures = abi.encodePacked(signature1, signature2);

        /// @dev Invalid ECDSA signature.
        bytes memory encodedSignatures = abi.encodePacked(strategy, signatures);
        bytes memory signatureInvalid;
        assembly {
            mstore(signatureInvalid, 65) // 65 empty bytes
        }
        vm.expectRevert("Invalid ECDSA signature");
        settlement.recoverSigner(
            ISettlement.Scheme.Eip712,
            digest,
            signatureInvalid
        );

        /// @dev EIP-1271 signature is invalid.
        address negativeTestCaseSigningContract = address(
            new NegativeTestCaseSigningContract()
        );
        encodedSignatures = abi.encodePacked(
            negativeTestCaseSigningContract,
            signatures
        );
        vm.expectRevert("EIP-1271 signature is invalid");
        settlement.recoverSigner(
            ISettlement.Scheme.Eip1271,
            digest,
            encodedSignatures
        );
    }

    function testEip712() external {
        /// @dev Malformed ECDSA signature.
        bytes memory signature1 = _sign(_USER_A_PRIVATE_KEY, digest);
        assembly {
            mstore(signature1, 66) // Set signature to 66 bytes instead of 65.
        }
        vm.expectRevert("Malformed ECDSA signature");
        settlement.recoverSigner(ISettlement.Scheme.Eip712, digest, signature1);
        assembly {
            mstore(signature1, 65) // Set signature back to 65 bytes.
        }
        settlement.recoverSigner(ISettlement.Scheme.Eip712, digest, signature1);
    }
}
