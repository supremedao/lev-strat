# Security Review for SupremeDao

## General Issues  

## Test Coverage is lacking  

The files in scope do not have full test coverage.


| File                                    | % Lines          | % Statements     | % Branches     | % Funcs        |
|-----------------------------------------|------------------|------------------|----------------|----------------|
| contracts/HFUnwindResolver.sol          | 0.00% (0/10)     | 0.00% (0/13)     | 0.00% (0/2)    | 0.00% (0/3)    |
| contracts/LeverageStrategy.sol          | 74.70% (62/83)   | 72.48% (79/109)  | 50.00% (8/16)  | 73.68% (14/19) |
| contracts/periphery/AuraUtils.sol       | 50.00% (4/8)     | 50.00% (4/8)     | 25.00% (2/8)   | 50.00% (3/6)   |
| contracts/periphery/BalancerUtils.sol   | 60.00% (18/30)   | 60.87% (28/46)   | 50.00% (2/4)   | 50.00% (3/6)   |
| contracts/periphery/CurveUtils.sol      | 77.27% (17/22)   | 82.14% (23/28)   | 33.33% (6/18)  | 83.33% (5/6)   |
| script/deploy.s.sol                     | 0.00% (0/4)      | 0.00% (0/5)      | 100.00% (0/0)  | 0.00% (0/2)    |
| test/utils/BaseLeverageStrategyTest.sol | 0.00% (0/20)     | 0.00% (0/20)     | 100.00% (0/0)  | 0.00% (0/2)    |
| test/utils/BaseTest.sol                 | 0.00% (0/1)      | 0.00% (0/2)      | 100.00% (0/0)  | 0.00% (0/1)    |
| Total                                   | 56.74% (101/178) | 58.01% (134/231) | 37.50% (18/48) | 55.56% (25/45) |

## LeverageStrategyStorage.sol  

### INF-1: Use specific compiler version 

It is generally recommended to compile and test with a specific target compiler version.

Recommendation:  
Change:
```
pragma solidity ^0.8.0; 
```

to:
```
pragma solidity 0.8.20; 
```



### INFO-1: Natspec is incomplete  


## LeverageStrategy.sol  

### HIGH-1: `_mintMultipleShares` mints the same amount of shares to all depositors once the Keeper/Controller invests  

Users are able to call `LeverageStrategy::deposit()` to deposit into the contract. The `_deposit` has been reworked to pull `WETH` from the user. This `WETH` remains in the contract until `investFromKeeper` or `investFromController` is called. 

`_mintMultipleShares` allocates the shares proportionally according to the number of deposits, not the actual amount deposited. This means that user's will not be getting the appropriate amount of shares.  

Recommendation:  
Rework the `_mintMultipleShares` to mint shares based on a depositor's provided collateral.  

### HIGH-2: `depositAndInvest` allows users free shares  

The `LeverageStrategy::depositAndInvest` function allows users to deposit and immediately invest into the strategy.

There is a lack of input validation for this function: a user can specify an arbitrary amount of assets but still specify `_debtAmount` > 0. 

As the price of the collateral `wsETH` that is provided to the CurveController can increase, this means that there are times when a user can increase the debt of the protocol and be minted shares for this.  

Recommendation:  
Enforce appropriate input validation. The `assets` provided should always be appropriate for the `_debtAmount` requested.  

### MEDIUM-1: Prices may change  

The amount of `crvUSD` issuable to the protocol is dependent on the amount of debt the protocol has access to. If the initial price for WETH is 2000 USDC and the price increases, then the protocol has access to more debt via CurveController. Where do these shares go? Currently they can be stolen by a user through `depositAndInvest`

Recommendation: 
Either the protocol becomes overcollateralized (what does this mean i.t.o. capital utilization?) or the protocol rebalances periodically to account for the delta of the assets.  

Question: how does the protocol handle a situation where it's position becomes liquidatable? Can it handle this? 

Question: `wstETH`  

### 