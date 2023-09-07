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

import "./interfaces/IAuraBooster.sol";
import "./interfaces/IBalancerVault.sol";
import "./interfaces/IcrvUSD.sol";
import "./interfaces/IcrvUSDController.sol";
import "./interfaces/IcrvUSDUSDCPool.sol";
import "./interfaces/IERC20.sol";

contract LeverageStrategy {
    // State variables

    IAuraBooster      public auraBooster;
    IBalancerVault    public balancerPool;
    IcrvUSD           public crvUSD;
    IcrvUSDController public crvUSDController;
    IcrvUSDUSDCPool   public crvUSDUSDCPool;

    IERC20            public wsteth;
    IERC20            public crvusd;
    IERC20            public usdc;
    IERC20            public coil;

    // mainnet addresses
    address public treasury; // recieves a fraction of yield
    address public _wstETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address public _crvUSD = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E;
    address public _USDC   = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public _COIL   = 0x823e1b82ce1dc147bbdb25a203f046afab1ce918;

    // pools addresses

    // https://etherscan.io/address/0x42fbd9f666aacc0026ca1b88c94259519e03dd67
    address public _COILSUSDCBalancerPool = 0x42FBD9F666AaCC0026ca1B88C94259519e03dd67;

    // TODO: check if the booster is the right contract
    // https://etherscan.io/address/0xa57b8d98dae62b26ec3bcc4a365338157060b234
    address public _auraBooster = 0xA57b8d98dAE62B26Ec3bcC4a365338157060B234;

    // https://etherscan.io/address/0x4dece678ceceb27446b35c672dc7d61f30bad69e
    address _crvUSDUSDCPool = 0x4dece678ceceb27446b35c672dc7d61f30bad69e;

    // Events
    // Add relevant events to log important contract actions/events

    // Constructor
    constructor(address _dao) {
        dao = _dao;

        auraBooster      = IAuraBooster(_auraBooster);
        balancerPool     = IBalancerVault(_auraBooster);
        crvUSD           = IcrvUSD(_crvUSD);
        crvUSDController = IcrvUSDController(_crvUSDController);
        crvUSDUSDCPool   = IcrvUSDUSDCPool(_crvUSDUSDCPool);
        wsteth           = IERC20(_wstETH);
        crvusd           = IERC20(_crvUSD);
        usdc             = IERC20(_USDC);
        coil             = IERC20(_COIL);
    }

    // Modifiers
    // TODO: check if we need this solution
    modifier onlyTreasury() {
        require(msg.sender == dao,
            "Only the DAO can call this function.");
        _;
    }

    // TODO:
    // Collateral health monitor


    // main contract functions
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