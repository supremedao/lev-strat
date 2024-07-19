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

import "../interfaces/IcrvUSD.sol";
import {IPPAgentV2JobOwner} from "../interfaces/IPPAgentV2JobOwner.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Token Addresses, Interfaces and Errors
/// @author SupremeDAO
/// @notice Provides constant addresses and interfaces for various tokens used in the contracts.
/// @dev This abstract contract defines addresses and interfaces for tokens like BAL, AURA, WETH, and others.
abstract contract Constants {
    /// @notice The address of the BAL token.
    address public constant BAL = 0xba100000625a3754423978a60c9317c58a424e3D;

    /// @notice The address of the AURA token.
    address public constant AURA = 0xC0c293ce456fF0ED870ADd98a0828Dd4d2903DBF;

    /// @notice The address of the WETH token.
    address public constant WETH = 0xdFCeA9088c8A88A76FF74892C1457C17dfeef9C1;

    /// @notice The ERC20 interface for wstETH token.
    IERC20 public constant wstETH = IERC20(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);

    /// @notice The ERC20 interface for USDC token.
    IERC20 public constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    /// @notice The ERC20 interface for D2D token.
    IERC20 public constant D2D = IERC20(0x43D4A3cd90ddD2F8f4f693170C9c8098163502ad);

    /// @notice The ERC20 interface for D2D/USDC Balancer Pool Token (BPT).
    IERC20 public constant D2D_USDC_BPT = IERC20(0x27C9f71cC31464B906E0006d4FcBC8900F48f15f);

    /// @notice The crvUSD token interface.
    IcrvUSD public constant crvUSD = IcrvUSD(0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E);

    // @notice The PowerAgent contract.
    IPPAgentV2JobOwner public constant AgentContract = IPPAgentV2JobOwner(0xc9ce4CdA5897707546F3904C0FfCC6e429bC4546);

    /// @dev Raised when an unknown executer attempts an action.
    error UnknownExecuter();

    /// @dev Raised when cancellation of a deposit is not allowed.
    error DepositCancellationNotAllowed();


    /// @dev Raised when ERC20 token transfer fails.
    error AURA_DepositFailed();

    /// @dev Raised when ERC20 token transferFrom fails.
    error ERC20_TransferFromFailed();

    /// @dev Raised when ERC20 token transfer fails.
    error ERC20_TransferFailed();

    // @dev Raised when approval execution is failed
    error ERC20_ApprovalFailed();

    /// @dev Raised when a zero deposit is attempted.
    error ZeroDepositNotAllowed();

    /// @dev Raised when a zero investment is attempted.
    error ZeroInvestmentNotAllowed();

    /// @dev Raised when an overloaded redeem function is incorrectly used.
    error UseOverLoadedRedeemFunction();
    // Cannot queue and execute in same block
    error InvalidUnwind();
    // Cannot queue and execuite in same block
    error InvalidInvest();

    /// @dev Raised when the percentage is larger than 100% or token address is invalid
    error InvalidInput();

    /// @dev Raised when the fee percentage is larger than 70%
    error InvalidFee();

    /// @dev Raised when the amount of investments > maxInvestments amount
    error InvestmentsOverflow();

    /// @dev Job is called from Power Agent was created not by a caller
    error InvalidJobOwner();

}

