forge build --silent && jq '.abi' ./out/LeverageStrategy.sol/LeverageStrategy.json > './exports/LeverageStrategy.json'

forge build --silent && jq '.abi' ./out/HFUnwindResolver.sol/StrategyResolver.json > './exports/StrategyResolver.json'