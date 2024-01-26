Flow 

Input

1. user deposit's `wstETH` into the contract

2. keeper `invests`

2.1 Transfers the `wstETH` to Curve Controller

2.2 Gets `curveUSD` in exchange

2.3 Swaps `curveUSD` to `USDC`  

2.4 Provide liquidity to Balancer Pool  (transfers `USDC` to Balancer)  

2.5 Deposits the LP tokens (`BPT`) to AURA and receives `AURA`

Output  

1. unstake  

2. unstake and withdraw AURA, `AURA` gets transferred from the contract

2.2 `BPT` gets transferred into the contract  

2.3 exit pool: this transfers `BPT` to the pool

2.3 `USDC` gets transferred into the contract

2.4 Exchange `USDC` for `curveUSD`

2.5 repay the `curveUSD` loan. Debt decreases  

2.6 But the `wtETH`? -> gets removed via `_removeCollateral` and transferred to the user

2.7 