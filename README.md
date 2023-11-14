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

## Development

Code formatting:
```
npm install --save-dev prettier prettier-plugin-solidity

npx prettier --write --plugin=prettier-plugin-solidity 'contracts/**/*.sol'
```

To run `solhint`:

```
npm install -g solhint

solhint 'contracts/**/*.sol'
```
