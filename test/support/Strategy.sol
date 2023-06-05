// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;
import {IERC20} from "../../src/interfaces/IERC20.sol";
import {ISettlement} from "../../src/interfaces/ISettlement.sol";
import {MultisigAuction, IMultisigAuction} from "../../src/MultisigAuction.sol";
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
        rewardOwedByAccount[msg.sender] = 0;
    }
}

interface IChainklinkAggregator {
    function latestAnswer() external view returns (uint256);
}

/**
 * Crude Chainlink oracle for demonstration purposes
 */
contract Oracle {
    address public usdc = 0x04068DA6C83AFCFA0e13ba15A6696662335D5B75;
    address public dai = 0x8D11eC38a3EB5E956B052f67Da8Bdc9bef8Abf3E;
    address public usdcOracle = 0x2553f4eeb82d5A26427b8d1106C51499CBa5D99c; // Chainlink decimals is 8 --in practice need to account for decimals difference
    address public daiOracle = 0x91d5DEFAFfE2854C7D02F50c80FA1fdc8A721e52; // Chainlink decimals is 8 --in practice need to account for decimals difference
    mapping(address => address) public chainlinkOracleByToken;

    constructor() {
        chainlinkOracleByToken[usdc] = usdcOracle;
        chainlinkOracleByToken[dai] = daiOracle;
    }

    function getChainlinkPrice(
        address token
    ) public view returns (uint256 price) {
        price = IChainklinkAggregator(chainlinkOracleByToken[token])
            .latestAnswer();
    }

    /**
     * @notice Given an amount in determine amount out after slippage
     */
    function calculateEquivalentAmountAfterSlippage(
        address _fromToken,
        address _toToken,
        uint256 _amountIn,
        uint256 _slippageBips
    ) external view returns (uint256 amountOut) {
        uint256 fromTokenPrice = getChainlinkPrice(_fromToken);
        uint256 toTokenPrice = getChainlinkPrice(_toToken);
        uint256 fromTokenDecimals = IERC20(_fromToken).decimals();
        uint256 toTokenDecimals = IERC20(_toToken).decimals();
        uint256 priceRatio = (10 ** toTokenDecimals * fromTokenPrice) /
            toTokenPrice;
        uint256 decimalsAdjustment;
        if (fromTokenDecimals >= toTokenDecimals) {
            decimalsAdjustment = fromTokenDecimals - toTokenDecimals;
        } else {
            decimalsAdjustment = toTokenDecimals - fromTokenDecimals;
        }
        uint256 amountOut;
        if (decimalsAdjustment > 0) {
            amountOut =
                (_amountIn * priceRatio * (10 ** decimalsAdjustment)) /
                10 ** (decimalsAdjustment + fromTokenDecimals);
        } else {
            amountOut = (_amountIn * priceRatio) / 10 ** toTokenDecimals;
        }
        amountOut = ((10000 - _slippageBips) * amountOut) / 10000;
    }
}

contract OpenFlowSwapper {
    MultisigAuction _multisigAuction;
    Oracle _oracle;
    address internal _fromToken;
    address internal _toToken;

    constructor(
        MultisigAuction multisigAuction,
        Oracle oracle,
        address fromToken,
        address toToken
    ) {
        _multisigAuction = multisigAuction;
        _fromToken = fromToken;
        _toToken = toToken;
        _oracle = oracle;
    }

    function _swap() internal {
        // Determine swap amounts
        uint256 amountIn = IERC20(_fromToken).balanceOf(address(this));
        uint256 slippageBips = 30; // 0.3%
        uint256 minAmountOut = _oracle.calculateEquivalentAmountAfterSlippage(
            _fromToken,
            _toToken,
            amountIn,
            slippageBips
        );

        // Create posthook
        ISettlement.Interaction[] memory preHooks;
        ISettlement.Interaction[]
            memory postHooks = new ISettlement.Interaction[](1);
        postHooks[0] = ISettlement.Interaction({
            target: address(this),
            value: 0,
            callData: abi.encodeWithSelector(Strategy.updateAccounting.selector)
        });
        ISettlement.Hooks memory hooks = ISettlement.Hooks({
            preHooks: preHooks,
            postHooks: postHooks
        });

        // Swap
        _multisigAuction.initiateSwap(
            IMultisigAuction.SwapOrder({
                fromToken: address(_fromToken),
                toToken: address(_toToken),
                amountIn: amountIn,
                minAmountOut: minAmountOut,
                recipient: address(this),
                hooks: hooks
            })
        );
    }
}

contract Strategy is OpenFlowSwapper {
    MasterChef public masterChef;
    address public asset; // Underlying want token is DAI
    address public reward; // Reward is USDC
    MultisigAuction public multisigAuction;

    constructor(
        address _asset,
        address _reward,
        MasterChef _masterChef,
        MultisigAuction _multisigAuction,
        Oracle _oracle
    ) OpenFlowSwapper(_multisigAuction, _oracle, _reward, _asset) {
        asset = _asset;
        reward = _reward;
        masterChef = _masterChef;
        multisigAuction = _multisigAuction;
        masterChef.accrueReward();

        // TODO: SafeApprove??
        IERC20(reward).approve(address(multisigAuction), type(uint256).max);
    }

    function estimatedEarnings() external view returns (uint256) {
        return masterChef.rewardOwedByAccount(address(this));
    }

    function harvest() external {
        masterChef.getReward();
        _swap();
    }

    function updateAccounting() public {}
}
