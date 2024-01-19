#!/bin/bash

# Install Forge dependencies
forge install

# Print the initial deploying message
echo "Deploying Leverage Strategy on Sepolia mainnet..."

source .env

read -p "Press enter to begin the deployment..."

forge script script/Deploy.s.sol:Deploy --rpc-url $RPC_URL --broadcast -vvvv --verify --delay 15 --watch --private-key $PRIVATE_KEY

read -p "Add leverage strategy to .env and press enter..."

source .env

forge script script/Deploy.resolver.sol:DeployResolver --rpc-url $RPC_URL --broadcast -vvvv --verify --delay 15 --watch --private-key $PRIVATE_KEY