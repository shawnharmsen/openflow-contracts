// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;
import {IERC20} from "../../src/interfaces/IERC20.sol";
import {ISettlement} from "../../src/interfaces/ISettlement.sol";
import {IVault} from "../../test/support/interfaces/IVault.sol";
import {IVaultRegistry} from "../../test/support/interfaces/IVaultRegistry.sol";

/// @notice Sample contract to demonstrate usage of pre-swap and post-swap hooks
/// to allow users to zap in and out of vaults.
/// @dev Problem: If a user requests a swap between ERC20 tokenA and yvTokenA
/// only one or two solvers may support this innately (Portls does, for instance).
/// This is an issue because it's critically important for solvers to be able to compete
/// for the best swap rate regardless of token wrapping.
/// @dev Solution: By allowing users to specify pre-swap and post-swap hooks a user
/// can perform the token wrapping and unwrapping (deposit/withdraw) themselves which opens up
/// the actual  underlying token swap to the complete pool of solvers. This will result in the
/// user getting access to a much larger pool of competitive swap rates.
contract YearnVaultInteractions {
    IVaultRegistry registry =
        IVaultRegistry(0x727fe1759430df13655ddb0731dE0D0FDE929b04);
    address public settlement;
    address public executionProxy;

    constructor(address _settlement) {
        settlement = _settlement;
        executionProxy = ISettlement(settlement).executionProxy();
    }

    /// @notice Deposit swapped tokens on behalf of a user (zap in)
    /// @dev Steps for zap in:
    /// - As per normal swap user approves the Settlement contract to spend their fromToken
    /// - During the initial payload generation user sets recipient to vault interactions (this contract)
    /// - A swap occurs and `toToken` is sent to this contract
    /// - In a user signed post-swap hook the user instructs the solver to call out to this contract
    /// and initiate a deposit where recipient is the user
    /// - This contract initiates a deposit on behalf of the user
    function deposit(address token, address recipient) external {
        require(msg.sender == executionProxy, "Only execution proxy");
        IVault vault = IVault(registry.latestVault(token));
        uint256 balance = IERC20(token).balanceOf(address(this));
        IERC20(token).approve(address(vault), type(uint256).max); // This contract should never hold tokens
        vault.deposit(balance, recipient);
    }

    /// @notice Withdraw from a vault before swapping (zap out)
    /// @dev Steps for zap out:
    /// - User approves vault interactions (this contract) to spend their yvToken
    /// - User constructs signed a pre-swap hook instructing the solver to call withdraw
    /// - Settlement authenticates payload.sender (signatory) as per normal swap flow
    /// - Pre-swap hook is called from execution proxy where authenticated signatory is
    /// appended to calldata
    /// - User's tokens are withdrawn and sent to Settlement
    /// - Settlement continues and performs the swap
    /// - Settlement makes sure the user receives the agreed upon `toToken` and `toAmount`
    function withdraw(address yvToken) external {
        require(msg.sender == executionProxy, "Only execution proxy");
        address signatory;
        assembly {
            signatory := shr(96, calldataload(sub(calldatasize(), 20)))
        }
        IVault vault = IVault(yvToken);
        uint256 amount = vault.balanceOf(signatory);
        vault.transferFrom(signatory, address(this), amount);
        vault.withdraw(type(uint256).max, address(settlement));
    }
}
