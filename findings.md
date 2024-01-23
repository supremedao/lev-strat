## General Questions  

1. How does the protocol handle a situation where it's position becomes liquidatable? Can it handle this? 
2. 


## Findings

### HIGH-1: `depositAndInvest` allows users free shares  

The `LeverageStrategy::depositAndInvest` function allows users to deposit and immediately invest into the strategy.

There is a lack of input validation for this function: a user can specify an arbitrary amount of assets but still specify `_debtAmount` > 0. 

As the price of the collateral `wsETH` that is provided to the CurveController can increase, this means that there are times when a user can increase the debt of the protocol and be minted shares for this.  

Recommendation:  
Enforce appropriate input validation. The `assets` provided should always be appropriate for the `_debtAmount` requested.    

### HIGH-2: A user can `withdraw` more than they supplied and DoS the `_invest` function  

During `LeverageStrategy::_withdraw` a part of the `balanceOf` of `wstETH` is earmarked to be withdrawn to the user.
But the user also gets the same percentage of the total `wstETH` deposited.

In other words someone who used `depositAndInvest` to invest 100 wstETH into the protocol, and the total supply is 1000 wstETH (already invested amount), then they would get 10% of the wstETH waiting to be invested, and 10% of the already invested amount (as per their shares). The 10% of the `wstETH` waiting to be invested is thus extra funds not belonging to that user.

In addition, this decreases the `wstETH` balance of this contract, but the `_invest` function expects those funds to still be present in totality due to this code:
```
        (uint256 wstEthAmount, uint256 startKeyId,) = _computeAndRebalanceDepsoitRecords();
```

This code loops through all the deposits awaiting investing and totals up the `wstETHAmount` that is expected to be present.

---

### MEDIUM-1: Prices may change  

The amount of `crvUSD` issuable to the protocol is dependent on the amount of debt the protocol has access to. If the initial price for WETH is 2000 USDC and the price increases, then the protocol has access to more debt via CurveController. Where do these shares go? Currently they can be stolen by a user through `depositAndInvest`

Recommendation: 
Either the protocol becomes overcollateralized (what does this mean i.t.o. capital utilization?) or the protocol rebalances periodically to account for the delta of the assets.  

### MEDIUM-2: Hardcoded slippage param makes the protocol vulnerable  

The `_unwindPosition` function uses a hardcoded `minAmountOut` of `1`: `_exitPool(bptAmount, 1, 1);`

Recommendation: either have the `amountOutMin` be calculated and specified by the `CONTROLLER` (which is trusted), or calculate it in the function.  

### MEDIUM-3: Custom `_convertToAssets` is not used in contract 

Although `_convertToAssets` is overridden in `LeverageStrategy` it uses a different function signature. This means the original `convertToAssets` is used during the custom `_withdraw` call.  

### MEDIUM-4: Withdrawals and Redemptions bypass custom `_convertToShares` and `_convertToAssets`  

`_convertToShares` is overloaded in `LeverageStrategy`, but because a user still calls `ERC4626::withdraw` to withdraw, the custom `_convertToShares` isn't used:  

```
    function previewWithdraw(uint256 assets) public view virtual returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Ceil);
    }
```

### MEDIUM-5: `checkCondition()` can be manipulated 

The `StrategyResolver::checkCondition` function checks that the CDP health has not decreased by 15%. There is no way to track the last time the strategy health has been checked. 

A malicious actor could front-run calls to `checkCondition()` (especially if these are made at regular intervals by PowerPools). Calling `updateHealthCheck()` right before `checkCondition()` will update the `lastHealthCheck` and cause it to always return `false`, potentially masking a deterioration in protocol health.

Recommendation: Make `updateHealthCheck` callable only once a set interval has passed.

### MEDIUM-6: A griefer can brick the `invest` functionality  

Unlikely due to no profit-motive, but has a critical impact on functionality, so worth highlighting as medium. 

By opening thousands of small deposits a griefer can create a scenario where the difference between `depositCounter` and `lastKeyUsed` is so large that it becomes impossible to execute in one block.

As the deposits are looped over, this in effect becomes an unbounded array with the same security issues.

---

### QA-1: Use specific solc version

Make sure to compile to a specific solc version.

### QA-2: Unnecessary `grantRole` during `initialization`  

The `initialize` function can only be called by an address that already has the `DEFAULT_ADMIN_ROLE`, granting it again is unnecessary  

### QA-3: Missing Natspec  

There are multiple instances of missing natspec: 

- `initialize` is missing the `N` paramater natspec  
- `setTokenIndex` is missing natspec
- `strategyHealth` is missing natspec
- `invest` is missing natspec
- `investFromKeeper` is missing natspec
- `unwindPositionFromKeeper` is missing natspec  
- `unwindPosition` is missing natspec
- `_convertToPercentage` is missing natspec
- ``

### QA-4: Unreachable code  

`_pushwstEth` and `_pullwstEth` revert on failure, thus `transferSuccess` can never be `false`.  

### QA-5: `_recordDeposit` unused return variable  

`_recordDeposit` declares a named return variable `recordKey`, but does not use it. Instead a new `uint256` named `currentKey` is created. It will be simpler to replace `currentKey` with `recordKey` and it will save gas.  

### QA-6: Pack `DepositRecord` for more efficient storage   

The `DepositRecord` struct code can be packed more efficiently for gas savings.

```
    struct DepositRecord {
        address depositor;
        address receiver;
        uint256 amount;
        DepositState state;
    }
```

Recommendation: 

```
    struct DepositRecord {
        DepositState state;
        address depositor;
        address receiver;
        uint256 amount;
    }
```  


### QA-7: Consider adding a variable and accompanying setter for the percentage to use with `chechCondition()`  

As time progresses the team is likely to gather more data on the performance of the assets. It is good practice to have a way to adjust the check parameters in response to market conditions.