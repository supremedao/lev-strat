pragma solidity ^0.8.0;

import {LeverageStrategy} from "./LeverageStrategy.sol";
import {Tokens} from "./periphery/Tokens.sol";

contract StrategyResolver is Tokens {
    LeverageStrategy public leverageStrategy;
    int256 private lastHealthCheck;

    constructor(address _leverageStrategyAddress) {
        leverageStrategy = LeverageStrategy(_leverageStrategyAddress);
    }

    function updateHealthCheck() public {
        lastHealthCheck = leverageStrategy.strategyHealth();
    }

    // Check if strategy health has decreased by 15% or more
    function checkCondition() public view returns (bool) {
        int256 currentHealth = leverageStrategy.strategyHealth();
        int256 fifteenPercentDecrease = (lastHealthCheck * 85) / 100;
        return currentHealth <= fifteenPercentDecrease;
    }

    function checkBalanceAndReturnCalldata() public view returns (bool flag, bytes memory cdata) {
        if (wstETH.balanceOf(address(leverageStrategy)) > 0) {
            cdata = abi.encodeWithSelector(leverageStrategy.investFromKeeper.selector, 1);
            flag = true;
        } else {
            cdata = bytes("");
            flag = false;
        }
        return (flag, cdata);
    }

    function checkAndReturnCalldata() public view returns (bool flag, bytes memory cdata) {
        if (checkCondition()) {
            cdata = abi.encodeWithSelector(leverageStrategy.unwindPositionFromKeeper.selector);
            flag = true;
        } else {
            cdata = bytes("");
            flag = false;
        }
        return (flag, cdata);
    }
}
