// SPDX-License-Identifier: BUSL 1.1
pragma solidity 0.8.19;
import "../interfaces/ISettlement.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/IEip1271SignatureValidator.sol";
import "../interfaces/ISignatureManager.sol";

library OrderLib {
    uint256 internal constant _UID_LENGTH = 56;

    // TODO: Move buildDigest and order methods here

    function extractOrderUidParams(
        bytes memory orderUid
    )
        internal
        pure
        returns (bytes32 orderDigest, address owner, uint32 validTo)
    {
        require(orderUid.length == _UID_LENGTH, "GPv2: invalid uid");
        assembly {
            orderDigest := mload(add(orderUid, 32))
            owner := shr(96, mload(add(orderUid, 64)))
            validTo := shr(224, mload(add(orderUid, 84)))
        }
    }

    function packOrderUidParams(
        bytes memory orderUid,
        bytes32 orderDigest,
        address owner,
        uint32 validTo
    ) internal pure {
        require(orderUid.length == _UID_LENGTH, "GPv2: uid buffer overflow");
        assembly {
            mstore(add(orderUid, 56), validTo)
            mstore(add(orderUid, 52), owner)
            mstore(add(orderUid, 32), orderDigest)
        }
    }
}
