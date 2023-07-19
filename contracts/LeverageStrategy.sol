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

contract LeverageStrategy {
    // State variables
    address public dao;

    // Events
    // Add relevant events to log important contract actions/events

    // Modifiers
    modifier onlyDao() {
        require(msg.sender == owner, "Only the contract owner can call this function.");
        _;
    }

    // Constructor
    constructor(address _dao) {
        dao = _dao;
    }

    // TODO:
    // Stake func
    // Withdraw func
    // Collateral health monitor

}
