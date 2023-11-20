// SPDX-License-Identifier: GPL-3.0-or-later

/*

________                                          ______________________ 
__  ___/___  ____________________________ ___________  __ \__    |_  __ \
_____ \_  / / /__  __ \_  ___/  _ \_  __ `__ \  _ \_  / / /_  /| |  / / /
____/ // /_/ /__  /_/ /  /   /  __/  / / / / /  __/  /_/ /_  ___ / /_/ / 
/____/ \__,_/ _  .___//_/    \___//_/ /_/ /_/\___//_____/ /_/  |_\____/  
              /_/                                                        
*/

import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import "./interfaces/ILeverageStrategy.sol";


pragma solidity ^0.8.0;

contract StrategyVault is ERC4626 {

    ILeverageStrategy levStrategy;

    constructor(
        ERC20 _asset,
        string memory _name,
        string memory _symbol,
        address _leverageStrategy
    ) ERC4626(_asset,_name, _symbol) {

        levStrategy = ILeverageStrategy(_leverageStrategy);


    }

    function totalAssets() public view virtual override returns (uint256) {
        return levStrategy.getTotalwstETHDeposited();
    }

     function beforeWithdraw(uint256 assets, uint256 shares) internal virtual override {
        levStrategy.withdrawInvestmentFromUser(assets);
     }

     function afterDeposit(uint256 assets, uint256 shares) internal virtual override {
        //Need to update deposit/invest function in Leverage Strategy in new issue
        // This function will send the wsteth to the lev strat contract
        // Then the PowerPool keeper will handle investing and unwinding from the strategy
     }

}