# Fixes needed to be made

Note: this file should be deleted once fixes are made. This file is created as the creator had no internet connection when the review and minor fixes was happening

## Low - changes that doesn't impact current logic of contracts
- Refactor codebase to make it more managable
    - break down contracts into multiple modular smart contracts with separation of concerns
- Make required state variables to immutable as those values won't change


## Medium - changes that change execution flow of code but doesn't change the logic of contracts
- remove initializeContracts function and shift the logic from initializeContracts to constructor
- have a two step process where contracts are being assigned on construction, but the main parameters are being initialized separately ,so the ownership of the strategy go from deployer to the DAO
- investment should be done by PowerPool keeper in order to save on gas, so we need a deposit function, however we can add depositAndInvest function in case users want to pay the gas fee themselves

## High - changes the logic (Execute sequenctially only)
1. Make the `invest` function open to everyone so that anyone can invest.
2. Make the `unwindPosition` function open to everyone so that anyone can unwind the position.
- `invest` and `unwindPosition` should be done by PowerPool keeper in order to save on gas, so we need a deposit function, however we can add depositAndInvest function in case users want to pay the gas fee themselves
3. rename `unwindPositionFromKeeper` to `redeemRewardsToMaintainCDP`
4. rename `swapReward` to `reinvestUsingRewards` and add reinvesting logic after swapping rewards to wstEth.
5. keep track of investment made by the user by providing a token in return. Hence, mint when user interacts with `invest` and burn when user interacts with `unwindPosition`.
6. ensure when keeper interacts using `reinvestUsingRewards` or `redeemRewardsToMaintainCDP`, no change in supply of tracking token happens.
