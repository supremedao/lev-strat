# Fixes needed to be made

Note: this file should be deleted once fixes are made. This file is created as the creator had no internet connection when the review and minor fixes was happening

## Low - changes that doesn't impact current logic of contracts
- Refactor codebase to make it more managable
    - break down contracts into multiple modular smart contracts with separation of concerns
- Make required state variables to immutable as those values won't change


## Medium - changes that change execution flow of code but doesn't change the logic of contracts
- remove initializeContracts function and shift the logic from initializeContracts to constructor
- remove setter functions that are not needed. (Setter function for variables that have been converted to immutable)

## High - changes the logic (Execute sequenctially only)
1. Make the `invest` function open to everyone so that anyone can invest.
2. Make the `unwindPosition` function open to everyone so that anyone can unwind the position.
3. rename `unwindPositionFromKeeper` to `redeemRewardsToMaintainCDP`
4. rename `swapReward` to `reinvestUsingRewards` and add reinvesting logic after swapping rewards to wstEth.
5. keep track of investment made by the user by providing a token in return. Hence, mint when user interacts with `invest` and burn when user interacts with `unwindPosition`.
6. ensure when keeper interacts using `reinvestUsingRewards` or `redeemRewardsToMaintainCDP`, no change in supply of tracking token happens.
