// SPDX-License-Identifier: GPL-3.0-or-later

/*
________                                          ______________________ 
__  ___/___  ____________________________ ___________  __ \__    |_  __ \
_____ \_  / / /__  __ \_  ___/  _ \_  __ `__ \  _ \_  / / /_  /| |  / / /
____/ // /_/ /__  /_/ /  /   /  __/  / / / / /  __/  /_/ /_  ___ / /_/ / 
/____/ \__,_/ _  .___//_/    \___//_/ /_/ /_/\___//_____/ /_/  |_\____/  
              /_/                                                        
*/

pragma solidity 0.8.20;

import "../interfaces/IAuraBooster.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IBasicRewards.sol";

/// @title Aura Utility Functions
/// @author SupremeDAO
/// @notice Provides utility functions for interacting with Aura Finance contracts.
/// @dev This abstract contract includes functions for depositing, withdrawing, and unstaking in Aura Finance.
abstract contract AuraUtils {

    /// @notice The Pool ID for Aura Finance.
    uint256 public constant AURA_PID = 107;

    /// @notice Address of the Aura Booster contract for deposit operations.
    IAuraBooster public constant AURA_BOOSTER = IAuraBooster(0xA57b8d98dAE62B26Ec3bcC4a365338157060B234);

    /// @notice Address of the Aura Vault for staking operations.
    IBasicRewards public constant AURA_VAULT = IBasicRewards(0xe39570EF26fB9A562bf26F8c708b7433F65050af);

    /// @notice Determines the token to be staked.
    /// @dev Should be overridden to return the specific token to stake in Aura.
    /// @return The IERC20 token to be staked.
    function _tokenToStake() internal view virtual returns (IERC20);

    /// @notice Deposits all available tokens into the Aura Booster.
    /// @dev Approves and then deposits all tokens held by this contract into Aura using the depositAll method.
    function _depositAllAura() internal {
        // Approve the Aura Booster to spend the token
        require(
            _tokenToStake().approve(address(AURA_BOOSTER), _tokenToStake().balanceOf(address(this))),
            "Approval failed"
        );
        // Deposit all tokens to Aura
        require(AURA_BOOSTER.depositAll(AURA_PID, true));
    }

    /// @notice Deposits a specific amount of tokens into the Aura Booster.
    /// @dev Approves and then deposits a specified amount of tokens into Aura.
    /// @param amount The amount of tokens to deposit.
    function _depositAura(uint256 amount) internal {
        // Approve the Aura Booster to spend the token
        require(_tokenToStake().approve(address(AURA_BOOSTER), amount), "Approval failed");
        // Deposit specified amount of tokens to Aura
        require(AURA_BOOSTER.deposit(AURA_PID, amount, true));
    }

    /// @notice Withdraws all tokens from the Aura Booster.
    /// @dev Withdraws all staked tokens from Aura.
    function _withdrawAllAura() internal {
        // Withdraw all staked tokens from Aura
        AURA_BOOSTER.withdrawAll(AURA_PID);
    }

    /// @notice Withdraws a specific amount of tokens from the Aura Booster.
    /// @dev Withdraws a specified amount of staked tokens from Aura.
    /// @param amount The amount of tokens to withdraw.
    function _withdrawAura(uint256 amount) internal {
        // Withdraw specified amount of staked tokens from Aura
        AURA_BOOSTER.withdraw(AURA_PID, amount);
    }

    /// @notice Unstakes and withdraws a specific amount of tokens from the Aura Vault.
    /// @dev Unstakes and withdraws a specified amount of tokens from Aura, including accrued rewards.
    /// @param amount The amount of tokens to unstake and withdraw.
    function _unstakeAndWithdrawAura(uint256 amount) internal {
        // Unstake specified amount and withdraw from Aura Vault
        AURA_VAULT.withdrawAndUnwrap(amount, true);
    }

    /// @notice Unstakes and withdraws all tokens from the Aura Vault.
    /// @dev Unstakes and withdraws all tokens from Aura, including accrued rewards.
    function _unstakeAllAndWithdrawAura() internal {
        // Unstake all tokens and withdraw from Aura Vault
        AURA_VAULT.withdrawAllAndUnwrap(true);
    }
}
