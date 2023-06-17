// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;
import "./support/Storage.sol";

contract SigningTest is Storage {
    bytes32 digest = bytes32(hex"1337");

    function testEip1271() external {
        bytes memory signature1 = _sign(_USER_A_PRIVATE_KEY, digest);
        bytes memory signature2 = _sign(_USER_B_PRIVATE_KEY, digest);
        bytes memory signatures = abi.encodePacked(signature1, signature2);

        /// @dev Signer not approved.
        bytes memory encodedSignatures = abi.encodePacked(
            strategy,
            _sign(
                _USER_A_PRIVATE_KEY,
                bytes32(hex"deadbeef") // Sign a random digest
            ),
            signature2
        );
        vm.expectRevert("Signer is not approved");
        settlement.recoverSigner(
            ISettlement.Scheme.Eip1271,
            digest,
            encodedSignatures
        );

        /// @dev Not enough signatures provided.
        encodedSignatures = abi.encodePacked(strategy, signature2);
        vm.expectRevert("Not enough signatures provided");
        settlement.recoverSigner(
            ISettlement.Scheme.Eip1271,
            digest,
            encodedSignatures
        );

        /// @dev Test digest not approved
        vm.expectRevert("Digest not approved");
        encodedSignatures = abi.encodePacked(strategy, signatures);
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
            mstore(signature1, 66) // Set to 66 bytes instead of 65
        }
        vm.expectRevert("Malformed ECDSA signature");
        settlement.recoverSigner(ISettlement.Scheme.Eip712, digest, signature1);

        /// @dev Valid signature.
        assembly {
            mstore(signature1, 65) // Set back to 65
        }
        settlement.recoverSigner(ISettlement.Scheme.Eip712, digest, signature1);
    }
}
