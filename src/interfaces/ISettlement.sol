// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface ISettlement {
    struct Order {
        bytes signature;
        bytes data;
        Payload payload;
    }

    struct Payload {
        SigningScheme signingScheme;
        address fromToken;
        address toToken;
        uint256 fromAmount;
        uint256 toAmount;
        address sender;
        address recipient;
        uint256 nonce;
        uint256 deadline;
    }

    enum SigningScheme {
        Eip712,
        Eip1271,
        EthSign
    }

    function executeOrder(Order memory) external;

    function buildDigest(Payload memory) external view returns (bytes32);

    function nonces(address) external view returns (uint256);

    function recoverSigner(
        ISettlement.SigningScheme,
        bytes memory,
        bytes32
    ) external returns (address);
}

interface EIP1271Verifier {
    function isValidSignature(
        bytes32 _hash,
        bytes calldata _signature
    ) external returns (bytes4 magicValue);
}

interface ISolver {
    function hook(bytes calldata data) external;
}
