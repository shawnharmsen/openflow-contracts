// SPDX-License-Identifier: BUSL 1.1
pragma solidity 0.8.19;
import "./interfaces/ISettlement.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/ISignatureManager.sol";
import "./interfaces/IEip1271SignatureValidator.sol";
import {SafeTransferLib, ERC20} from "solmate/utils/SafeTransferLib.sol";
import {SigningLib} from "./lib/Signing.sol";

contract Settlement {
    using SafeTransferLib for ERC20;
    bytes32 private constant _DOMAIN_NAME = keccak256("Blockswap");
    bytes32 private constant _DOMAIN_VERSION = keccak256("v0.0.1");
    bytes32 private constant _DOMAIN_TYPE_HASH =
        keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        );
    bytes32 public constant TYPE_HASH =
        keccak256(
            "Swap(uint8 signingScheme,address fromToken,address toToken,uint256 fromAmount,uint256 toAmount,address sender,address recipient,uint256 nonce,uint256 deadline)"
        );
    bytes32 public immutable domainSeparator;
    mapping(address => uint256) public nonces;

    constructor() {
        domainSeparator = keccak256(
            abi.encode(
                _DOMAIN_TYPE_HASH,
                _DOMAIN_NAME,
                _DOMAIN_VERSION,
                block.chainid,
                address(this)
            )
        );
    }

    function _verify(ISettlement.Order calldata order) internal {
        bytes32 digest = buildDigest(order.payload);
        address signatory = SigningLib.recoverSigner(
            order.payload.signingScheme,
            order.signature,
            digest
        );
        require(signatory == order.payload.sender, "Invalid signer");
        require(block.timestamp <= order.payload.deadline, "Deadline expired");
        require(
            order.payload.nonce == nonces[signatory]++,
            "Nonce already used"
        );
    }

    event OrderExecuted(
        address solver,
        address sender,
        address fromToken,
        address toToken,
        uint256 fromAmount,
        uint256 toAmount
    );
    bytes4 private constant _EIP1271_MAGICVALUE = 0x1626ba7e;

    function executeOrder(ISettlement.Order calldata order) public {
        ISettlement.Payload memory payload = order.payload;
        _verify(order);
        ERC20(payload.fromToken).safeTransferFrom(
            payload.sender,
            msg.sender,
            payload.fromAmount
        );
        uint256 outputTokenBalanceBefore = ERC20(payload.toToken).balanceOf(
            payload.recipient
        );
        ISolver(msg.sender).hook(order.data);
        uint256 outputTokenBalanceAfter = ERC20(payload.toToken).balanceOf(
            payload.recipient
        );
        uint256 balanceDelta = outputTokenBalanceAfter -
            outputTokenBalanceBefore;
        require(balanceDelta >= payload.toAmount, "Order not filled");
        emit OrderExecuted(
            tx.origin,
            payload.sender,
            payload.fromToken,
            payload.toToken,
            payload.fromAmount,
            payload.toAmount
        );
    }

    // See SigUtils.sol for a less optimized and more readable version
    // TODO: Compare gas savings of using this method
    function buildDigest(
        ISettlement.Payload memory payload
    ) public view returns (bytes32 orderDigest) {
        bytes32 typeHash = TYPE_HASH;
        bytes32 structHash;
        bytes32 _domainSeparator = domainSeparator;
        uint256 structLength = bytes(abi.encode(payload)).length;
        assembly {
            let dataStart := sub(payload, 32)
            let temp := mload(dataStart)
            mstore(dataStart, typeHash)
            structHash := keccak256(dataStart, add(structLength, 0x20))
            mstore(dataStart, temp)
        }
        assembly {
            let freeMemoryPointer := mload(0x40)
            mstore(freeMemoryPointer, "\x19\x01")
            mstore(add(freeMemoryPointer, 2), _domainSeparator)
            mstore(add(freeMemoryPointer, 34), structHash)
            orderDigest := keccak256(freeMemoryPointer, 66)
        }
    }
}
