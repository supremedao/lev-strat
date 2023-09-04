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
    address public DAO;
    address public wstETH;
    address public crvUSD;
    address public USDC;

    // TODO write pools addresses
    address public COILSUSDCBalancerPool;
    address public COILSUSDCAuraPool;

    // Events
    // Add relevant events to log important contract actions/events

    // Constructor
    constructor(address _dao) {
        DAO = _dao;
    }


    // Modifiers
    modifier onlyDao() {
        require(msg.sender == DAO,
            "Only the DAO can call this function.");
        _;
    }

    // TODO:
    // Collateral health monitor

    function _invest(address, uint256[] calldata amounts, bytes calldata)
        internal
        override
        returns (PositionReceipt memory receipt)
    {

        // Takes WSTETH

        // Opens a position on crvUSD

        // borrow crvUSD

        // Exchange crvUSD to USDC on Curve

        // Provide liquidity to the COIL/USDC Pool on Balancer

        // Stake LP tokens on Aura Finance

    }

    function _claimRewards(address, bytes calldata) internal override {
        // Claim rewards from Aura

        // exchange for WSTETH

        // call _invest
    }

    function _withdrawInvestment(address, uint256[] calldata amounts, bytes calldata extraStrategyData)
        internal
        override
    {

        // Exit Aura position

        // Exit Balancer position

        // Exchange everything to crvUSD

        // repay debt

        // withdraw colleteral

    }
}