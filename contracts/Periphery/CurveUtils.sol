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
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./Tokens.sol";

abstract contract CurveUtils is Tokens {
    // fix: address of crvUSD will not change, we can set it as immutable
    IcrvUSDController public constant crvUSDController = IcrvUSDController(0x100dAa78fC509Db39Ef7D04DE0c1ABD299f4C6CE);
    IcrvUSDUSDCPool public constant crvUSDUSDCPool = IcrvUSDUSDCPool(0x4DEcE678ceceb27446b35C672dC7d61F30bAD69E);

    uint256 public totalWsthethDeposited; // Total wsteth deposited
    uint256 public totalUsdcAmount; // Total usdc  after swapping from crvusd
    uint256 internal N; // Number of bands for the crvusd/wseth soft liquidation range

    /// @notice Create a loan position for the strategy, only used if this is the first position created
    /// @param _wstETHAmount the amount of wsteth deposited
    /// @param _debtAmount the amount of crvusd borrowed
    function _depositAndCreateLoan(uint256 _wstETHAmount, uint256 _debtAmount) internal {
        require(_wstETHAmount > 0, "Amount should be greater than 0");

        //require(IERC20(wsteth).transferFrom(msg.sender, address(this), _wstETHAmount), "Transfer failed");

        require(wstETH.approve(address(crvUSDController), _wstETHAmount), "Approval failed");

        // Call create_loan on the controller
        crvUSDController.create_loan(_wstETHAmount, _debtAmount, N);

        totalWsthethDeposited = totalWsthethDeposited + _wstETHAmount;
    }

    /// @notice Add collateral to a loan postion if the poistion is already initialised
    /// @param _wstETHAmount the amount of wsteth deposited
    function _addCollateral(uint256 _wstETHAmount) internal {
        require(_wstETHAmount > 0, "Amount should be greater than 0");

        require(wstETH.transferFrom(msg.sender, address(this), _wstETHAmount), "Transfer failed");

        require(wstETH.approve(address(crvUSDController), _wstETHAmount), "Approval failed");

        crvUSDController.add_collateral(_wstETHAmount, address(this));
        totalWsthethDeposited = totalWsthethDeposited + _wstETHAmount;
    }

    /// @notice Borrow more crvusd,
    /// @param _wstETHAmount the amount of wsteth deposited
    /// @param _debtAmount the amount of crvusd borrowed
    /// @dev We don't need to transferFrom msg.sender anymore as now the wsteth will be directly transferred by the vault
    function _borrowMore(uint256 _wstETHAmount, uint256 _debtAmount) internal {
        require(wstETH.approve(address(crvUSDController), _wstETHAmount), "Approval failed");

        crvUSDController.borrow_more(_wstETHAmount, _debtAmount);

        totalWsthethDeposited = totalWsthethDeposited + _wstETHAmount;
    }

    function _repayCRVUSDLoan(uint256 deptToRepay) internal {
        require(crvUSD.approve(address(crvUSDController), deptToRepay), "Approval failed");
        crvUSDController.repay(deptToRepay);
    }

    function _exchangeCRVUSDtoUSDC(uint256 _dx) internal {
        require(crvUSD.approve(address(crvUSDUSDCPool), _dx), "Approval failed");

        uint256 expected = crvUSDUSDCPool.get_dy(1, 0, _dx) * 99 / 100;

        crvUSDUSDCPool.exchange(1, 0, _dx, expected, address(this));
        totalUsdcAmount = USDC.balanceOf(address(this));
    }

    function _exchangeUSDCTocrvUSD(uint256 _dx) internal {
        require(USDC.approve(address(crvUSDUSDCPool), _dx), "Approval failed");
        uint256 expected = crvUSDUSDCPool.get_dy(0, 1, _dx) * 99 / 100;
        crvUSDUSDCPool.exchange(0, 1, _dx, expected, address(this));
        totalUsdcAmount = USDC.balanceOf(address(this));
    }
}
