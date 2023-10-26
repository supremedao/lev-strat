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

import "./interfaces/IAuraClaimZapV3.sol";
import "./interfaces/IAuraBooster.sol";
import "./interfaces/IBalancerVault.sol";
import "./interfaces/IcrvUSD.sol";
import "./interfaces/IcrvUSDController.sol";
import "./interfaces/IcrvUSDUSDCPool.sol";
import "./interfaces/IERC20.sol";

contract LeverageStrategy {

    //Struct to keep strack of the users funds and where they are allocated
    //TODO: see how many of the struct vars actually need the full uint256
    struct UserInfo {
        uint256 wstETHDeposited;
        uint256 crvUSDBorrowed;
        uint256 usdcAmount;
        uint256 balancerLPTokens;
        uint256 stakedInAura;
        uint256 totalYieldEarned;
        uint256 loanBand;
    }

    // State variables

    IAuraClaimZapV3   public auraClaim;
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

    //mappings
    mapping(address => UserInfo) public userInfo;

    // pools addresses

    // TODO:
    // DAO should be able to change pool parameters and tokens
    // NOTE: maybe we should an updateble strategy struct

    // https://etherscan.io/address/0x42fbd9f666aacc0026ca1b88c94259519e03dd67
    address public _COILSUSDCBalancerPool = 0x42FBD9F666AaCC0026ca1B88C94259519e03dd67;

    // TODO: check if the booster is the right contract
    // https://etherscan.io/address/0xa57b8d98dae62b26ec3bcc4a365338157060b234
    address public _auraBooster = 0xA57b8d98dAE62B26Ec3bcC4a365338157060B234;

    // https://etherscan.io/address/0x5b2364fd757e262253423373e4d57c5c011ad7f4#code
    address public _auraClaim = 0x5b2364fD757E262253423373E4D57C5c011Ad7F4;

    // https://etherscan.io/address/0x4dece678ceceb27446b35c672dc7d61f30bad69e
    address _crvUSDUSDCPool = 0x4dece678ceceb27446b35c672dc7d61f30bad69e;

    // Events
    // Add relevant events to log important contract actions/events

    // Constructor
    constructor(address _dao) {
        dao = _dao;
        auraClaim        = IAuraClaimZapV3(_auraClaim);
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


     function depositAndCreateLoan(uint256 _wstETHAmount, uint256 _debtAmount, uint256 _N) internal {
        require(_wstETHAmount > 0, "Amount should be greater than 0");
        
        require(IERC20(wstETH).transferFrom(msg.sender, address(this), _wstETHAmount), "Transfer failed");         
        require(IERC20(wstETH).approve(address(controller), _wstETHAmount), "Approval failed");
        
        // Call create_loan on the controller
        controller.create_loan(_wstETHAmount, _debtAmount, _N);
        
        // Update the user's info
        UserInfo storage user = userInfo[msg.sender];
        user.wstETHDeposited = user.wstETHDeposited.add(_wstETHAmount);
        user.crvUSDBorrowed = user.crvUSDBorrowed.add(_debtAmount);
        user.loanBand = _N;
    }

    // main contract functions
    function invest(uint256 _wstETHAmount, uint256 _debtAmount, uint256 _N) external {
        
        // Opens a position on crvUSD if no loan already
        if (!crvUSDController.loan_exists(address(this))){
        
        depositAndCreateLoan(_wstETHAmount, _debtAmount, _N);

        }

        // Note this address is an owner of a crvUSD CDP
        // now we assume that we already have a CDP
        // But there also should be a case when we create a new one

        crvUSDController.add_collateral(uint256 collateral, address(this));

        // borrow crvUSD

        // TODO: calculate borrow amount
        // check if there's price in Curve or we should ping Oracle
        uint256 borrowAmount;

        crvUSDController.borrow_more(amount, borrowAmount);

        // Exchange crvUSD to USDC on Curve

        // TODO: check the actual token id's and transaction generation
        // Note: seems that we have a different interface compared to supremedao/contracts

        // pool crvUSD -> USDCPool
        // For this Pool:
        // token_id 0 = crvUSD
        // token_id 2 = USDCPool
        crvUSDUSDCPool.exchange({ sold_token_id: 0, bought_token_id: 2, amount: amounts[0], min_output_amount: min_output_amount });

        // Provide liquidity to the COIL/USDC Pool on Balancer
        bytes32 _poolId = 0x42fbd9f666aacc0026ca1b88c94259519e03dd67000200000000000000000507;

        // TODO: compose a JoinPoolRequest struct

        balancerPool.joinPool(_poolId, address(this), address(this) /*JoinPoolRequest*/);

        // Stake LP tokens on Aura Finance
        uint pid = 95;

        auraBooster.deposit(pid, borrowAmount, true);
    }

    function _claimRewards() external {

        // Claim rewards from Aura

        // TODO: figure out how to pass all the parameters
        auraClaim.claimRewards();

        // exchange for WSTETH

        // Note: there is no BAL/AURA -> WSTETH Pool
        // TODO: check if there is a single transaction on Balancer
        // otherwise do a jumping transaction BAL -> ETH -> WSTETH

        // call _invest

        uint256 investAmount;
        _invest(investAmount);
    }

// TODO: exit pool

    function _withdrawInvestment(address, uint256[] calldata amounts, bytes calldata extraStrategyData)
        external
    {

        // Exit Aura position

        // Exit Balancer position

        // Exchange everything to crvUSD

        // repay debt

        // withdraw colleteral

    }
}
