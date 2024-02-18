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

/// @title Leverage Strategy Storage Contract
/// @author SupremeDAO
/// @notice This abstract contract serves as a storage module for the Leverage Strategy, 
///         holding state variables, structured data, and events used across the strategy implementation.
/// @dev This contract defines the essential storage structure including deposits, 
///      state variables related to investment and borrowing, and custom error messages. 
///      It doesn't contain logic for strategy execution but is inherited by contracts that do.
abstract contract LeverageStrategyStorage {

    /// @dev Represents the various states a deposit can be in.
    enum DepositState {
        NO_DEPOSIT,  // No deposit made.
        DEPOSITED,   // Deposit has been made.
        INVESTED,    // Deposit has been invested.
        CANCELLED    // Deposit has been cancelled.
    }

    /// @notice Index of the token to be withdrawn when exiting the pool.
    uint256 internal TokenIndex;

    /// @notice Total amount of crvUSD borrowed.
    uint256 public crvUSDBorrowed;

    /// @notice Total Balancer LP tokens held by the contract.
    uint256 public totalBalancerLPTokens;

    /// @notice Total Balancer LP tokens staked in Aura Finance by the user.
    uint256 public totalStakedInAura;

    /// @notice Address that receives a fraction of the yield.
    address public treasury;

    /// @notice Percentage buffer to use, default 5%
    uint256 public healthBuffer = 5e10;

    /// @dev Struct to keep track of each deposit.
    struct DepositRecord {
        DepositState state;
        address depositor;
        address receiver;
        uint256 amount;
    }

    struct QueuedAction {
        uint64 timestamp;
        uint192 minAmountOut;
    }

    /// @notice Counter for deposit records.
    uint256 public depositCounter;

    /// @notice Last used key in the deposit mapping.
    uint256 public lastUsedDepositKey;

    /// @notice Mapping of deposit records.
    mapping(uint256 => DepositRecord) public deposits;

    // The queued unwind
    QueuedAction public unwindQueued;
    QueuedAction public investQueued;

    /// @notice Emitted when a deposit is made.
    /// @param depositKey The key of the deposit in the mapping.
    /// @param amount The amount of the deposit.
    /// @param sender The address of the sender who made the deposit.
    /// @param receiver The address of the receiver for the deposit.
    event Deposited(uint256 indexed depositKey, uint256 amount, address indexed sender, address indexed receiver);

    /// @notice Emitted when a deposit is cancelled.
    /// @param depositKey The key of the cancelled deposit in the mapping.
    event DepositCancelled(uint256 indexed depositKey);

}
