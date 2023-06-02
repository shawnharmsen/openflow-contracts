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
        IERC20(reward).approve(profitEscrow, type(uint256).max);
    }

    function harvest() external {
        masterChef.getReward();
    }

    function updateAccounting() public {}
}

// The only thing this contract can do is take reward from the strategy, sell them, and return profits
contract StrategyProfitEscrow {
    bytes4 private constant _EIP1271_MAGICVALUE = 0x1626ba7e;
    bytes4 private constant _EIP1271_NOTALLOWED = 0xffffffff;
    mapping(bytes32 => bool) public digestApproved;
    ISettlement public settlement; // TODO: Get from factory

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
    }

    function isValidSignature(
        bytes32 digest,
        bytes calldata signature
    ) external view returns (bytes4) {
        // Check if digest is approved
        if (digestApproved[digest]) {
            return _EIP1271_MAGICVALUE;
        }
        return _EIP1271_NOTALLOWED;
    }

    function approveSwap(
        uint256 fromAmount,
        uint256 toAmount
    ) external returns (ISettlement.Payload memory payload) {
        // Enforce any logic re: minAmountOut here
        fromToken.transferFrom(address(strategy), address(this), fromAmount);
        fromToken.approve(address(settlement), fromAmount);
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
        bytes32 digest = settlement.buildDigest(payload);
        digestApproved[digest] = true;
    }
}
