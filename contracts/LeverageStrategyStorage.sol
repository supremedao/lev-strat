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

    /// @notice Role identifier for the keeper role, responsible for protocol maintenance tasks. Role given to PowerAgent
    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");

    /// @notice Role identifier for the controller role, responsible for high-level protocol management
    bytes32 public constant CONTROLLER_ROLE = keccak256("CONTROLLER_ROLE");

    /// @notice Role identifier for the caller role, responsible for high-level protocol management
    bytes32 public constant CALLER_ROLE = keccak256("CALLER_ROLE");


    /// @notice Fixed percentage (scaled by 10^12) used in unwinding positions, default set to 30%
    uint256 public unwindPercentage = 30 * 10 ** 10;

    /// @notice Constant representing 100%, used for percentage calculations, scaled by 10^12
    uint256 public constant HUNDRED_PERCENT = 10 ** 12;

    /// @notice Max percentage of fees on leverage transferred to DAO
    uint256 public MAX_DAO_FEE = 70 * HUNDRED_PERCENT / 100;


    /// @notice Amount of wstEth in the contract, that was deposited but is not yet invested
    uint256 public deposited = 0;

    /// @notice The maximal amount of investments processed by the strategy
    uint256 public maxInvestment = 100 ether;

    /// @notice The amount of current investments in the contract
    uint256 public currentDeposits = 0;

    /// @dev Represents the various states a deposit can be in.
    enum DepositState {
        DEPOSITED,   // Deposit has been made.
        INVESTED    // Deposit has been invested.
    }

    /// @notice Address that receives a fraction of the yield.
    address public controller;

    /// @notice Percentage buffer to use, default 5%
    uint256 public healthBuffer = 5e10;

    /// @notice Percentage of funds, transferred to DAO
    uint256 public fee = 60 * HUNDRED_PERCENT / 100;

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
