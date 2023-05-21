// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface ISettlement {
    struct Order {
        bytes signature;
        bytes data;
        address solver;
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
}

interface EIP1271Verifier {
    function isValidSignature(
        bytes32 _hash,
        bytes calldata _signature
    ) external view returns (bytes4 magicValue);
}

interface ISolver {
    function hook(bytes calldata data) external;
}
