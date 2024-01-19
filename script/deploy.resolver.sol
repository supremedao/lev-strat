// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {StrategyResolver} from "../contracts/HFUnwindResolver.sol";
import "forge-std/Script.sol";

contract DeployResolver is Script {
    function setUp() public {}

    function run() public {
        // get pvt key from env file, log associated address
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address levStart = vm.envAddress("LEV_STRAT");

        vm.startBroadcast();
        StrategyResolver resolver = new StrategyResolver(levStart);
        vm.stopBroadcast();
    }
}
