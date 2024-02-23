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
import "../interfaces/IcrvUSDController.sol";
import "../interfaces/IcrvUSDUSDCPool.sol";
import "./Constants.sol";

/// @title Curve Utility Functions
/// @author SupremeDAO
/// @notice Provides utility functions for interacting with Curve Finance contracts.
/// @dev This abstract contract includes functions for depositing, borrowing, repaying, and exchanging assets on Curve.
abstract contract CurveUtils is Constants {
    /// @notice The controller contract for crvUSD loans.
    IcrvUSDController public constant crvUSDController = IcrvUSDController(0x100dAa78fC509Db39Ef7D04DE0c1ABD299f4C6CE);

    /// @notice The Curve pool for crvUSD and USDC exchange.
    IcrvUSDUSDCPool public constant crvUSDUSDCPool = IcrvUSDUSDCPool(0x4DEcE678ceceb27446b35C672dC7d61F30bAD69E);

    /// @notice Total amount of wstETH deposited.
    uint256 public totalWsthethDeposited;

    /// @notice Number of bands for the crvusd/wstETH soft liquidation range.
    uint256 public N;

    /// @notice Creates a loan position using wstETH as collateral.
    /// @dev Used only for the initial creation of a loan position.
    /// @param _wstETHAmount The amount of wstETH to be deposited as collateral.
    /// @param _debtAmount The amount of crvUSD to be borrowed.
    function _depositAndCreateLoan(uint256 _wstETHAmount, uint256 _debtAmount) internal {
        if (_wstETHAmount == 0) {
            revert ZeroDepositNotAllowed();
        }

        // Approve the crvUSDController to handle wstETH
        if (!wstETH.approve(address(crvUSDController), _wstETHAmount)) {
            revert ERC20_ApprovalFailed();
        }

        // Call create_loan on the controller
        crvUSDController.create_loan(_wstETHAmount, _debtAmount, N);

        // Update the total wstETH deposited after creating the loan
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
        // Approve the crvUSDController to handle additional wstETH
        if (!wstETH.approve(address(crvUSDController), _wstETHAmount)) {
            revert ERC20_ApprovalFailed();
        }

        // Borrow more crvUSD against the additional wstETH collateral
        crvUSDController.borrow_more(_wstETHAmount, _debtAmount);
        totalWsthethDeposited += _wstETHAmount;
    }

    /// @notice Repays a specified amount of the crvUSD loan.
    /// @param debtToRepay The amount of crvUSD to repay.
    function _repayCRVUSDLoan(uint256 debtToRepay) internal {
        // Approve the crvUSDController to handle additional wstETH
        if (!crvUSD.approve(address(crvUSDController), debtToRepay)) {
            revert ERC20_ApprovalFailed();
        }
        // Repay the specified amount of crvUSD loan
        crvUSDController.repay(debtToRepay);
    }

    /// @notice Exchanges crvUSD to USDC through the Curve pool.
    /// @param _dx The amount of crvUSD to exchange.
    function _exchangeCRVUSDtoUSDC(uint256 _dx) internal {
        if (!crvUSD.approve(address(crvUSDUSDCPool), _dx)) {
            revert ERC20_ApprovalFailed();
        }

        // Calculate the expected USDC amount and perform the exchange
        uint256 expected = crvUSDUSDCPool.get_dy(1, 0, _dx) * 99 / 100;
        crvUSDUSDCPool.exchange(1, 0, _dx, expected, address(this));
    }

    /// @notice Exchanges USDC to crvUSD through the Curve pool.
    /// @param _dx The amount of USDC to exchange.
    function _exchangeUSDCTocrvUSD(uint256 _dx) internal {
        if (!USDC.approve(address(crvUSDUSDCPool), _dx)) {
            revert ERC20_ApprovalFailed();
        }

        // Calculate the expected crvUSD amount and perform the exchange
        uint256 expected = crvUSDUSDCPool.get_dy(0, 1, _dx) * 99 / 100;
        crvUSDUSDCPool.exchange(0, 1, _dx, expected, address(this));
    }
}
