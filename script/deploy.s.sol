// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {LeverageStrategy} from "../contracts/LeverageStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
//import {MockERC20} from "../contracts/utils/MockERC20.sol";
import "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

contract Deploy is Script {
    LeverageStrategy internal levStrat;

    function setUp() public {}

    function run() public {
        address account = vm.addr(0x1);
        console2.log("account:", account);

        vm.startBroadcast();
        /**
         * address dao = msg.sender;
         *             address AuraBooster= 0xA57b8d98dAE62B26Ec3bcC4a365338157060B234;
         *             address balancerVault= 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
         *             address crvUSD= 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E;
         *             address crvUSDController= 0x100dAa78fC509Db39Ef7D04DE0c1ABD299f4C6CE;
         *             address crvUSDUSDCPool= 0x4DEcE678ceceb27446b35C672dC7d61F30bAD69E;
         *             address wstETH= 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
         *             address usdc= 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
         *             address d2d= 0x43D4A3cd90ddD2F8f4f693170C9c8098163502ad;
         *             address d2dusdcBPT= 0x27C9f71cC31464B906E0006d4FcBC8900F48f15f;
         *             address AuraLPVault= 0xe39570EF26fB9A562bf26F8c708b7433F65050af;
         *
         *             levStrat = new LeverageStrategy(dao);
         *
         *             levStrat.setTokenIndex(1);
         *             levStrat.setPoolId(0x27c9f71cc31464b906e0006d4fcbc8900f48f15f00020000000000000000010f);
         *             levStrat.setPid(107);
         *
         *             levStrat.initializeContracts(
         *                 AuraBooster,
         *                 balancerVault,
         *                 crvUSD,
         *                 crvUSDController,
         *                 crvUSDUSDCPool,
         *                 wstETH,
         *                 usdc,
         *                 d2d
         *             );
         *
         *             levStrat.setBPTAddress(d2dusdcBPT);
         *             levStrat.setVaultAddress(AuraLPVault);
         */
        vm.startBroadcast();
    }
}
