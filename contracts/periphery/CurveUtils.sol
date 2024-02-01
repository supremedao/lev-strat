// SPDX-License-Identifier: GPL-3.0-or-later

/*
________                                          ______________________ 
__  ___/___  ____________________________ ___________  __ \__    |_  __ \
_____ \_  / / /__  __ \_  ___/  _ \_  __ `__ \  _ \_  / / /_  /| |  / / /
____/ // /_/ /__  /_/ /  /   /  __/  / / / / /  __/  /_/ /_  ___ / /_/ / 
/____/ \__,_/ _  .___//_/    \___//_/ /_/ /_/\___//_____/ /_/  |_\____/  
              /_/                                                        
*/

pragma solidity ^0.8.0;

import "../interfaces/IcrvUSD.sol";
import "../interfaces/IcrvUSDController.sol";
import "../interfaces/IcrvUSDUSDCPool.sol";
import "../interfaces/ILLAMMA.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./Tokens.sol";

/// @title Curve Utility Functions
/// @author SupremeDAO
/// @notice Provides utility functions for interacting with Curve Finance contracts.
/// @dev This abstract contract includes functions for depositing, borrowing, repaying, and exchanging assets on Curve.
abstract contract CurveUtils is Tokens {
    /// @notice The controller contract for crvUSD loans.
    IcrvUSDController public constant crvUSDController = IcrvUSDController(0x100dAa78fC509Db39Ef7D04DE0c1ABD299f4C6CE);

    /// @notice The Curve pool for crvUSD and USDC exchange.
    IcrvUSDUSDCPool public constant crvUSDUSDCPool = IcrvUSDUSDCPool(0x4DEcE678ceceb27446b35C672dC7d61F30bAD69E);
    ILlamma public constant curveAMM = ILlamma(0x37417B2238AA52D0DD2D6252d989E728e8f706e4);

    /// @notice Total amount of wstETH deposited.
    uint256 public totalWsthethDeposited;

    /// @notice Total amount of USDC after exchanging from crvUSD.
    uint256 public totalUsdcAmount;

    /// @notice Number of bands for the crvusd/wstETH soft liquidation range.
    uint256 public N;

    /// @notice Creates a loan position using wstETH as collateral.
    /// @dev Used only for the initial creation of a loan position.
    /// @param _wstETHAmount The amount of wstETH to be deposited as collateral.
    /// @param _debtAmount The amount of crvUSD to be borrowed.
    function _depositAndCreateLoan(uint256 _wstETHAmount, uint256 _debtAmount) internal {
        require(_wstETHAmount > 0, "Amount should be greater than 0");

        // Approve the crvUSDController to handle wstETH
        require(wstETH.approve(address(crvUSDController), _wstETHAmount), "Approval failed");

        // Call create_loan on the controller
        crvUSDController.create_loan(_wstETHAmount, _debtAmount, N);

        // Update the total wstETH deposited after creating the loan
        totalWsthethDeposited += _wstETHAmount;
    }

    /// @notice Adds more collateral to an existing loan position.
    /// @dev The wstETH is already held by the contract, so no transfer is needed.
    /// @param _wstETHAmount The amount of wstETH to add as additional collateral.
    function _addCollateral(uint256 _wstETHAmount) internal {
        require(_wstETHAmount > 0, "Amount should be greater than 0");

        // Approve the crvUSDController to handle additional wstETH
        require(wstETH.approve(address(crvUSDController), _wstETHAmount), "Approval failed");

        // Add the additional collateral to the existing loan
        crvUSDController.add_collateral(_wstETHAmount, address(this));
        totalWsthethDeposited += _wstETHAmount;
    }

    /// @notice Removes the collateral from the controller
    /// @param  withdrawalAmount The amount of wstETH to withdraw
    function _removeCollateral(uint256 withdrawalAmount) internal {
        crvUSDController.remove_collateral(withdrawalAmount, false);
        totalWsthethDeposited -= withdrawalAmount;
    }

    /// @notice Borrows additional crvUSD against the collateral.
    /// @param _wstETHAmount The amount of wstETH deposited as collateral for the additional borrowing.
    /// @param _debtAmount The amount of crvUSD to borrow.
    function _borrowMore(uint256 _wstETHAmount, uint256 _debtAmount) internal {
        require(wstETH.approve(address(crvUSDController), _wstETHAmount), "Approval failed");

        // Borrow more crvUSD against the additional wstETH collateral
        crvUSDController.borrow_more(_wstETHAmount, _debtAmount);
        totalWsthethDeposited += _wstETHAmount;
    }

    /// @notice Repays a specified amount of the crvUSD loan.
    /// @param debtToRepay The amount of crvUSD to repay.
    function _repayCRVUSDLoan(uint256 debtToRepay) internal {
        require(crvUSD.approve(address(crvUSDController), debtToRepay), "Approval failed");

        // Repay the specified amount of crvUSD loan
        crvUSDController.repay(debtToRepay);
    }

    /// @notice Exchanges crvUSD to USDC through the Curve pool.
    /// @param _dx The amount of crvUSD to exchange.
    function _exchangeCRVUSDtoUSDC(uint256 _dx) internal {
        require(crvUSD.approve(address(crvUSDUSDCPool), _dx), "Approval failed");

        // Calculate the expected USDC amount and perform the exchange
        uint256 expected = crvUSDUSDCPool.get_dy(1, 0, _dx) * 99 / 100;
        uint256 beforeUsdcBalance = USDC.balanceOf(address(this));
        crvUSDUSDCPool.exchange(1, 0, _dx, expected, address(this));
        totalUsdcAmount += USDC.balanceOf(address(this)) - beforeUsdcBalance;
    }

    /// @notice Exchanges USDC to crvUSD through the Curve pool.
    /// @param _dx The amount of USDC to exchange.
    function _exchangeUSDCTocrvUSD(uint256 _dx) internal {
        require(USDC.approve(address(crvUSDUSDCPool), _dx), "Approval failed");

        // Calculate the expected crvUSD amount and perform the exchange
        uint256 expected = crvUSDUSDCPool.get_dy(0, 1, _dx) * 99 / 100;
        uint256 beforeUsdcBalance = USDC.balanceOf(address(this));
        crvUSDUSDCPool.exchange(0, 1, _dx, expected, address(this));
        totalUsdcAmount -= beforeUsdcBalance - USDC.balanceOf(address(this));
    }
}
