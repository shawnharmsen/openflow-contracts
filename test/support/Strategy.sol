// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;
import {IERC20} from "../../src/interfaces/IERC20.sol";
import {ISettlement} from "../../src/interfaces/ISettlement.sol";
import "forge-std/Test.sol";

contract MasterChef {
    mapping(address => uint256) public rewardOwedByAccount;
    IERC20 public rewardToken =
        IERC20(0x04068DA6C83AFCFA0e13ba15A6696662335D5B75); // USDC

    // Allow anyone to accrue reward for testing purposes
    function accrueReward() external {
        rewardOwedByAccount[msg.sender] += 1e6;
    }

    // Mock reward earning. In reality user will probably call deposit or withdraw with amount set to zero to initialize a reward earn
    function getReward() external {
        uint256 amountOwed = rewardOwedByAccount[msg.sender];
        if (amountOwed > 0) {
            rewardToken.transfer(msg.sender, amountOwed);
        }
    }
}

contract Strategy {
    MasterChef masterChef;
    address public asset = 0x8D11eC38a3EB5E956B052f67Da8Bdc9bef8Abf3E; // Underlying want token is DAI
    address public reward; // Reward is USDC
    address public profitEscrow;

    constructor(MasterChef _masterChef, address settlement) {
        masterChef = _masterChef;
        masterChef.accrueReward();
        reward = address(masterChef.rewardToken());
        profitEscrow = address(
            new StrategyProfitEscrow(address(this), settlement, reward, asset)
        );
    }

    function harvest() external {
        masterChef.getReward();
        IERC20(reward).transfer(
            profitEscrow,
            IERC20(reward).balanceOf(address(this))
        );
    }

    function updateAccounting() public {}
}

// The only thing this contract can do is take reward from the strategy, sell them, and return profits
contract StrategyProfitEscrow {
    bytes4 private constant _EIP1271_MAGICVALUE = 0x1626ba7e;
    bytes4 private constant _EIP1271_NOTALLOWED = 0xffffffff;
    mapping(bytes32 => bool) public digestApproved;
    ISettlement public settlement; // TODO: Get from factory
    mapping(address => bool) public signers;

    IERC20 fromToken; // reward
    IERC20 toToken; // asset
    Strategy strategy;

    constructor(
        address _strategy,
        address _settlement,
        address _fromToken,
        address _toToken
    ) {
        strategy = Strategy(_strategy);
        fromToken = IERC20(_fromToken);
        toToken = IERC20(_toToken);
        settlement = ISettlement(_settlement);
        fromToken.approve(_settlement, type(uint256).max);
    }

    function addSigners(address[] memory _signers) external {
        for (uint256 signerIdx; signerIdx < _signers.length; signerIdx++) {
            signers[_signers[signerIdx]] = true;
        }
    }

    function checkNSignatures(
        bytes32 digest,
        bytes memory signatures,
        uint256 requiredSignatures
    ) public {
        require(
            signatures.length >= requiredSignatures * 65,
            "Invalid signature length"
        );
        address lastOwner;
        address currentOwner;

        for (uint256 i = 0; i < requiredSignatures; i++) {
            bytes memory signature;
            assembly {
                let signaturePos := add(sub(signatures, 28), mul(0x41, i))
                mstore(signature, 65)
                calldatacopy(add(signature, 0x20), signaturePos, 65)
            }
            currentOwner = settlement.recoverSigner(
                ISettlement.SigningScheme.Eip712,
                signature,
                digest
            );
            require(
                currentOwner > lastOwner && signers[currentOwner],
                "Invalid signature order"
            );
            lastOwner = currentOwner;
        }
    }

    function isValidSignature(
        bytes32 digest,
        bytes calldata signatures
    ) external returns (bytes4) {
        uint256 requiredSignatures = 2;
        checkNSignatures(digest, signatures, requiredSignatures);

        // TODO: is important to return 0xffffffff on failure or is revert sufficient
        return _EIP1271_MAGICVALUE;
    }

    function generatePayload(
        uint256 fromAmount,
        uint256 toAmount
    ) public returns (ISettlement.Payload memory payload) {
        payload = ISettlement.Payload({
            signingScheme: ISettlement.SigningScheme.Eip1271,
            fromToken: address(fromToken),
            toToken: address(toToken),
            fromAmount: fromAmount,
            toAmount: toAmount,
            sender: address(this),
            recipient: address(strategy),
            nonce: settlement.nonces(address(this)),
            deadline: block.timestamp
        });
    }

    function buildDigest(
        uint256 fromAmount,
        uint256 toAmount
    ) external returns (bytes32 digest) {
        digest = settlement.buildDigest(generatePayload(fromAmount, toAmount));
    }
}
