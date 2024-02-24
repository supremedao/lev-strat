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

import {LeverageStrategy, BalancerUtils} from "./LeverageStrategy.sol";
import {Constants} from "./periphery/Constants.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title  StrategyResolver
/// @notice Used by PowerPool to check and manage protocol health
/// @dev    Allows the PowerPool to check and receive the appropriate calldata for automated function calls
contract StrategyResolver is Ownable, Constants {
    // The target strategy contract
    LeverageStrategy public leverageStrategy;
    
    // Threshholds
    // The minimum Strategy health acceptable. `0` by default.
    int256 public unwindThreshold;
    // The minimum amount of WETH required to invoke `investFromKeeper`, 1 ETH by default.
    // Note the front-running risk in using a threshold
    uint256 public investThreshold = 1 ether;
    // Health threshold at which to reinvest
    int256 public reinvestThreshold = 1e17;

    /// @param _leverageStrategyAddress Address of the target Strategy contract
    constructor(address _leverageStrategyAddress) Ownable(msg.sender) {
        leverageStrategy = LeverageStrategy(_leverageStrategyAddress);
    }

    /// @notice Check used by the Power Pool to determine when to rebalance the strategy
    /// @return Returns a `bool` indicating whether the PowerPool should unwind or not
    /*
                Scenario 1: The Strategy health is less than `threshold`
                            In this scenario the Strategy Health has fallen below the set `threshold`
                            Rebalancing should occur to unwind some of the debt positions.

                Why don't we store `strategyHealth` locally and check against that?
                `controller.health()` gives us an up to date value for the strategy's health.
                This value is true at that block. 

                Note the assumption: the only way that `health` deteriorates is if the `wstETH` price falls

                There should be no other way in the protocol for the user to alter the `health` of the strategy.
                
                If the user `withdraws`, then they can only withdraw in proportion; they clear their debt and withdraw,
                i.e. no change in health. 

                If the user `deposits`, then the shares minted are in proportion to the `wstETH` provided, with a slight buffer.
    */
    function checkCondition() public view returns (bool) {
        int256 currentHealth = leverageStrategy.strategyHealth();

        return currentHealth <= unwindThreshold;
    }

    /// @notice Used by Keeper to check if there is any balance to invest
    function checkBalanceAndReturnCalldata() public view returns (bool flag, bytes memory cdata) {
        (uint64 timeQueued,) = leverageStrategy.investQueued();
        // There is a reinvest queued
        if (timeQueued != 0 && leverageStrategy.strategyHealth() > reinvestThreshold) {
            cdata = abi.encodeWithSelector(leverageStrategy.executeInvestFromKeeper.selector, 1, true);
            flag = true;
            return (flag, cdata);
        // No reinvest needed, but investments needed
        } else if (timeQueued != 0) {
            cdata = abi.encodeWithSelector(leverageStrategy.executeInvestFromKeeper.selector, 1, false);
            flag = true;
            return (flag, cdata);
        }

        // If the Strategy is too healthy we need to utilise the excess collateral
        if (leverageStrategy.strategyHealth() > reinvestThreshold) {
            cdata = abi.encodeWithSelector(leverageStrategy.investFromKeeper.selector);
            flag = true;
        } else if (wstETH.balanceOf(address(leverageStrategy)) > investThreshold) {
        // Funds in the contract awaiting invest
            cdata = abi.encodeWithSelector(leverageStrategy.investFromKeeper.selector);
            flag = true;
        } else {
            cdata = bytes("");
            flag = false;
        }
        return (flag, cdata);
    }

    /// @notice This function returns the calldata for the Keeper to execute
    /// @dev    Only to be used by Keeper to obtain correct calldata
    function checkAndReturnCalldata() public view returns (bool flag, bytes memory cdata) {
        // If there is an unwind waiting to be called
        (uint64 timeQueued,) = leverageStrategy.unwindQueued();
        if (timeQueued != 0) {
            cdata = abi.encodeWithSelector(leverageStrategy.executeUnwindFromKeeper.selector);
            return (true, cdata);
        }

        // If there was no unwind queued we check the current health
        if (checkCondition()) {
            cdata = abi.encodeWithSelector(leverageStrategy.unwindPositionFromKeeper.selector);
            flag = true;
        } else {
            cdata = bytes("");
            flag = false;
        }
        return (flag, cdata);
    }

    /// @notice Allows owner to set the amount of wstETH that should be in the contract before the keeper invests it
    /// @dev    Access controlled
    /// @param  amount Amount of wstETH that should accrue in Strategy before it will be invested automatically
    function setInvestThreshold(uint256 amount) external onlyOwner {
        investThreshold = amount;
    }

    /// @notice Allows owner to set the acceptable `health` threshold before the keeper unwinds debt
    /// @dev    Access controlled
    /// @dev    Be careful! This can be negative.
    /// @param  newThreshold Amount of wstETH that should accrue in Strategy before it will be invested automatically
    function setUnwindThreshold(int256 newThreshold) external onlyOwner {
        unwindThreshold = newThreshold;
    }


    /// @notice Allows owner to set the acceptable `health` threshold before the keeper increases the debt
    /// @dev    Access controlled
    /// @dev    Be careful! This can be negative, although is not recommended to be.
    /// @param  newThreshold Amount of wstETH that should accrue in Strategy before it will be invested automatically
    function setReinvestThreshold(int256 newThreshold) external onlyOwner {
        unwindThreshold = newThreshold;
    }
}
