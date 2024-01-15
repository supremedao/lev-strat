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

abstract contract LeverageStrategyStorage {
    // State variables
    uint256 internal TokenIndex;
    uint256 public crvUSDBorrowed; // Total crvusd borrowed
    uint256 public totalBalancerLPTokens; // Total balancer LP tokens the
    uint256 public totalStakedInAura; // Total balancer LP tokens staked in aura for the user
    address public treasury; // recieves a fraction of yield
}
