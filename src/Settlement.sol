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

    event OrderExecuted(
        address solver,
        address sender,
        address fromToken,
        address toToken,
        uint256 fromAmount,
        uint256 toAmount
    );

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

    /**
     * @notice Primary method for order execution
     * @dev TODO: Add more comments
     */
    function executeOrder(ISettlement.Order calldata order) public {
        ISettlement.Payload memory payload = order.payload;

        /**
         * @notice Step 1. Verify the integrity of the order
         * @dev Verifies that payload.sender signed the order
         * @dev Only the order payload is signed
         * @dev Once an order is signed anyone who has the signature can fufil the order
         * @dev In the case of smart contracts sender must implement EIP-1271 isVerified method
         */
        _verify(order);

        /**
         * @notice Step 2. Optimistically transfer funds from payload.sender to msg.sender (order executor)
         * @dev Payload.sender must approve settlement
         * @dev TODO: We probably don't need safe transfer anymore here since we are checking balances now
         */
        ERC20(payload.fromToken).safeTransferFrom(
            payload.sender,
            msg.sender,
            payload.fromAmount
        );
        uint256 outputTokenBalanceBefore = ERC20(payload.toToken).balanceOf(
            payload.recipient
        );

        /**
         * @notice Step 3. Order executor executes the swap and is required to send funds to payload.recipient
         * @dev Order executors can be completely custom, or the generic order executor can be used
         * @dev Solver configurable metadata about the order is sent to the order executor hook
         * @dev Settlement does not care how the solver executes the order, all Settlement cares about is that
         *      the user receives the minimum amount of tokens the signer agreed to
         */
        ISolver(msg.sender).hook(order.data); // TODO: Consider if there are any security implications based on ERC777 hooks

        /**
         * @notice Step 4. Make sure payload.recipient receives the agreed upon amount of tokens
         */
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

    /**
     * @notice Order verification
     * @dev TODO: Add more comments
     */
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

    /**
     * @notice Building the digest hash
     * @dev See SigUtils.sol for a less optimized and more readable version
     * @dev TODO: Compare SigUtils implementation vs this impleemntation for gas savings analysis
     * @dev TODO: Add more comments
     */
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
