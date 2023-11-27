// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {LeverageStrategy} from "../contracts/LeverageStrategy.sol";
import {StrategyVault} from "../contracts/StrategyVault.sol";
import {IERC20} from "../contracts/interfaces/IERC20.sol";
//import {MockERC20} from "../contracts/utils/MockERC20.sol";
import "forge-std/Script.sol";

contract Deploy is Script {

    LeverageStrategy internal levStrat;
    StrategyVault internal vault;
    MockERC20 internal lpToken;

    function run(address dao,address AuraBooster, address balancerVault , address crvUSD, address crvUSDController,
    address crvUSDUSDCPool, address wstETH, address usdc, address d2d, address d2dusdcBPT, address AuraLPVault ) public {

        //lpToken = new MockERC20("StratLP","SLP",18);

        levStrat = new LeverageStrategy(dao);

        levStrat.setTokenIndex(1);
        levStrat.setPoolId(0x27c9f71cc31464b906e0006d4fcbc8900f48f15f00020000000000000000010f);
        levStrat.setPid(107);

        levStrat.initializeContracts(
            AuraBooster,
            balancerVault,
            crvUSD,
            crvUSDController,
            crvUSDUSDCPool,
            wstETH,
            usdc,
            d2d
        );

        levStrat.setBPTAddress(d2dusdcBPT);
        levStrat.setVaultAddress(AuraLPVault);

        //vault = new StrategyVault(lpToken,"StratLP","SLP",address(levStrat));



       // levStrat.setVaultAddress(address(vault));

    }
}