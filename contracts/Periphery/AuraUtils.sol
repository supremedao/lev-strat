// SPDX-License-Identifier: GPL-3.0-or-later

/*
________                                          ______________________ 
__  ___/___  ____________________________ ___________  __ \__    |_  __ \
_____ \_  / / /__  __ \_  ___/  _ \_  __ `__ \  _ \_  / / /_  /| |  / / /
____/ // /_/ /__  /_/ /  /   /  __/  / / / / /  __/  /_/ /_  ___ / /_/ / 
/____/ \__,_/ _  .___//_/    \___//_/ /_/ /_/\___//_____/ /_/  |_\____/  
              /_/                                                        
*/

pragma solidity ^0.8.0;

import "../interfaces/IAuraBooster.sol";
import "../interfaces/IBalancerVault.sol";
import "../interfaces/IcrvUSD.sol";
import "../interfaces/IcrvUSDController.sol";
import "../interfaces/IcrvUSDUSDCPool.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/IBasicRewards.sol";
import "./Tokens.sol";

abstract contract AuraUtils {
    uint256 public constant AURA_PID = 107;
    //address of aura smart contract
    IAuraBooster public constant AURA_BOOSTER = IAuraBooster(0xA57b8d98dAE62B26Ec3bcC4a365338157060B234);
    IBasicRewards public constant AURA_VAULT = IBasicRewards(0xe39570EF26fB9A562bf26F8c708b7433F65050af);

    function _tokenToStake() internal view virtual returns (IERC20);

    function _depositAllAura() internal {
        require(
            _tokenToStake().approve(address(AURA_BOOSTER), _tokenToStake().balanceOf(address(this))), "Approval failed"
        );
        require(AURA_BOOSTER.depositAll(AURA_PID, true));
    }

    function _depositAura(uint256 ammount) internal {
        require(_tokenToStake().approve(address(AURA_BOOSTER), ammount), "Approval failed");
        require(AURA_BOOSTER.deposit(AURA_PID, ammount, true));
    }

    function _withdrawAllAura() internal {
        AURA_BOOSTER.withdrawAll(AURA_PID);
    }

    function _withdrawAura(uint256 ammount) internal {
        AURA_BOOSTER.withdraw(AURA_PID, ammount);
    }

    function _unstakeAndWithdrawAura(uint256 amount) internal {
        AURA_VAULT.withdrawAndUnwrap(amount, true);
    }

    function _unstakeAllAndWithdrawAura() internal {
        AURA_VAULT.withdrawAllAndUnwrap(true);
    }
}
