// SPDX-License-Identifier: GPL-3.0
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
        /// @dev EIP-1271 signature is invalid.
        address negativeTestCaseSigningContract = address(
            new NegativeTestCaseSigningContract()
        );
        bytes memory encodedSignatures = abi.encodePacked(
            negativeTestCaseSigningContract
        );
        vm.expectRevert("EIP-1271 signature is invalid");
        settlement.recoverSigner(
            ISettlement.Scheme.Eip1271,
            digest,
            encodedSignatures
        );
    }

    function testEip712() external {
        /// @dev Invalid ECDSA signature.
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

    function testSignatureThreshold() external {
        /// @dev Build digest.
        ISettlement.Hooks memory hooks;
        ISettlement.Condition memory condition;
        ISettlement.Payload memory payload = ISettlement.Payload({
            fromToken: address(0),
            toToken: address(0),
            fromAmount: 0,
            toAmount: 0,
            sender: userA,
            recipient: userA,
            validFrom: uint32(block.timestamp),
            validTo: uint32(block.timestamp),
            scheme: ISettlement.Scheme.Eip712,
            condition: condition,
            driver: address(0),
            hooks: hooks
        });
        digest = settlement.buildDigest(payload);

        /// @dev Sign digest and perform valid threshold check.
        bytes memory signature1 = _sign(_USER_A_PRIVATE_KEY, digest);
        bytes memory signature2 = _sign(_USER_B_PRIVATE_KEY, digest);
        bytes memory signatures = abi.encodePacked(signature1, signature2);
        driver.checkNSignatures(digest, signatures);

        /// @dev Invalid signature order or duplicate signature.
        signatures = abi.encodePacked(signature2, signature1);
        vm.expectRevert("Invalid signature order or duplicate signature");
        driver.checkNSignatures(digest, signatures);

        /// @dev User A presigns payload.
        startHoax(userA);
        bytes memory orderUid = settlement.submitOrder(payload);
        bytes32 r = bytes32(abi.encodePacked(userA));
        assembly {
            r := shr(96, r)
        }
        bytes32 s;
        uint8 v = 1;
        signature1 = abi.encodePacked(r, s, v);
        signatures = abi.encodePacked(signature1, signature2);
        driver.checkNSignatures(digest, signatures);

        /// @dev Now invalidate the presigned order
        settlement.invalidateOrder(orderUid);
        vm.expectRevert("Order not presigned");
        driver.checkNSignatures(digest, signatures);

        /// @dev Sign the order again
    }
}
