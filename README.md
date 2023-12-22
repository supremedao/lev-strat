# Lavereged WstETH Strategy for SupremeDAO on PowerPool


Download and install Foundry:
```
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

Install OZ:
```
forge install OpenZeppelin/openzeppelin-contracts
```

Remap dependencies for hardhat: 
```
forge remappings > remappings.txt
```

Test:
```
forge test --fork-url https://eth-mainnet.g.alchemy.com/v2/M4H2wIh8657p_bF11PxNM2ZyaPPU6n6R -vvvvv

```

## What are the flows?


Depicted are the following user flows:

### Deposit WSTETH to be used in strategy

Users can deposit their WSTETH and earn a yield on it from the protocol strategy it out by calling the `deposit` function on the `strategyVault` directly.

### Withdraw deposited WSTETH

Users can withdraw their deposited WSTETH from the depositorVault with the `withdraw` function, the strategy will be converting rewards to wsteth and sending it to the vault so when users redeem from the vault they will be getting a share of the rewards

### Call Invest from Controller

Controller calls the invest function with the amounts of uint256 _wstETHAmount uint256 _debtAmount uint256 _bptAmountOut which will invest in the strategy

### Call Unwind from Controller

Controller calls the unwindPosition()  function with an array of amounts of uint256 to specify how much to unwind from each step

### Call unwindPositionFromKeeper
This is the call that gets called by the powerPool keeper to unwind 30% of the postion, it gets called when health factor does below a set %


