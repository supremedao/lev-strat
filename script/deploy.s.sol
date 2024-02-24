// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {LeverageStrategy} from "../contracts/LeverageStrategy.sol";
import "forge-std/Script.sol";

contract Deploy is Script {
    function setUp() public {}

    function run() public {
        // get pvt key from env file, log associated address
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        bytes32 poolId = vm.envBytes32("POOL_ID");

        vm.startBroadcast();
        LeverageStrategy levStrat = new LeverageStrategy(poolId);
        vm.stopBroadcast();
    }
}
