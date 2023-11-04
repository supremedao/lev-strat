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


import "@openzeppelin/contracts/access/AccessControl.sol";
import "./interfaces/IAuraClaimZapV3.sol";
import "./interfaces/IAuraBooster.sol";
import "./interfaces/IBalancerVault.sol";
import "./interfaces/IcrvUSD.sol";
import "./interfaces/IcrvUSDController.sol";
import "./interfaces/IcrvUSDUSDCPool.sol";
import "./interfaces/IERC20.sol";

contract LeverageStrategy {

    //Struct to keep track of the users funds and where they are allocated
    //TODO: see how many of the struct vars actually need the full uint256
    struct UserInfo {
        uint256 wstETHDeposited; // Total wsteth deposited by a user
        uint256 crvUSDBorrowed; // Total crvusd borrowed by a user
        uint256 usdcAmount; // Total usdc of the user after swapping from crvusd

        uint256 balancerLPTokens;  // Total balancer LP tokens the user 
        uint256 stakedInAura;// Total balancer LP tokens staked in aura for the user
        uint256 totalYieldEarned;// Historical yield for the user, maybe unnecessary 
        uint256 loanBand;// The number of price bands in which the users wsteth will be deposited into
    }

    // State variables
    IAuraClaimZapV3   public auraClaim;
    IAuraBooster      public auraBooster;
    IBalancerVault    public balancerVault;
    IcrvUSD           public crvUSD;
    IcrvUSDController public crvUSDController;
    IcrvUSDUSDCPool   public crvUSDUSDCPool;

    IERC20            public wsteth;
    IERC20            public crvusd;
    IERC20            public usdc;
    IERC20            public d2d;

    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");
    bytes32 public constant DAO_ROLE = keccak256("DAO_ROLE");
    uint256           public totalwstETHDeposited;

    // mainnet addresses
    address public treasury; // recieves a fraction of yield
    address public _wstETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address public _crvUSD = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E;
    address public _USDC   = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public _D2D   = 0x43d4a3cd90ddd2f8f4f693170c9c8098163502ad;

    //mappings
    mapping(address => UserInfo) public userInfo;

    // pools addresses

    // TODO:
    // DAO should be able to change pool parameters and tokens
    // NOTE: maybe we should an updateble strategy struct

    // https://etherscan.io/address/0x27c9f71cc31464b906e0006d4fcbc8900f48f15f
    address public _D2DSUSDCBalancerPool = 0x27C9f71cC31464B906E0006d4FcBC8900F48f15f;

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
        treasury = _dao;
        auraClaim        = IAuraClaimZapV3(_auraClaim);
        auraBooster      = IAuraBooster(_auraBooster);
        balancerVault     = IBalancerVault(_auraBooster);
        crvUSD           = IcrvUSD(_crvUSD);
        crvUSDController = IcrvUSDController(_crvUSDController);
        crvUSDUSDCPool   = IcrvUSDUSDCPool(_crvUSDUSDCPool);

        wsteth           = IERC20(_wstETH);
        crvusd           = IERC20(_crvUSD);
        usdc             = IERC20(_USDC);
        coil             = IERC20(_COIL);
    
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(DAO_ROLE, _dao);
    }


    /// @dev This helper function is a fast and cheap way to convert between IERC20[] and IAsset[] types
    function _convertERC20sToAssets(IERC20[] memory tokens) internal pure returns (IAsset[] memory assets) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            assets := tokens
        }
    }

    
    // TODO:
    // Collateral health monitor


    /// @notice Create a loan position for the strategy, only used if this is the first position created
    /// @param _wstETHAmount the amount of wsteth deposited
    /// @param _debtAmount the amount of crvusd borrowed
    /// @param _N the number of price bins wsteth is deposited into, this is for crvusds soft liquidations
     function _depositAndCreateLoan(uint256 _wstETHAmount, uint256 _debtAmount, uint256 _N) internal {
        require(_wstETHAmount > 0, "Amount should be greater than 0");
        
        require(IERC20(wstETH).transferFrom(msg.sender, address(this), _wstETHAmount), "Transfer failed");         
        require(IERC20(wstETH).approve(address(controller), _wstETHAmount), "Approval failed");
        
        // Call create_loan on the controller
        controller.create_loan(_wstETHAmount, _debtAmount, _N);

        totalwstETHDeposited = totalwstETHDeposited + _wstETHAmount;
        
        // Update the user's info
        UserInfo storage user = userInfo[msg.sender];
        user.wstETHDeposited = user.wstETHDeposited.add(_wstETHAmount);
        user.crvUSDBorrowed = user.crvUSDBorrowed.add(_debtAmount);
        user.loanBand = _N;
    }


    /// @notice Add collateral to a loan postion if the poistion is already initialised
    /// @param _wstETHAmount the amount of wsteth deposited
    function _addCollateral(uint256 _wstETHAmount) internal {

        crvUSDController.add_collateral(_wstETHAmount, address(this));
        totalwstETHDeposited = totalwstETHDeposited + _wstETHAmount;

    }


    /// @notice Borrow more crvusd,
    /// @param _wstETHAmount the amount of wsteth deposited
    /// @param _debtAmount the amount of crvusd borrowed
    function _borrowMore(uint256 _wstETHAmount, uint256 _debtAmount) internal {

        crvUSDController.borrow_more(_wstETHAmount, _debtAmount);

        // Update the user's info
        UserInfo storage user = userInfo[msg.sender];
        user.wstETHDeposited = user.wstETHDeposited.add(_wstETHAmount);
        user.crvUSDBorrowed = user.crvUSDBorrowed.add(_debtAmount);
        
    }

    /// @notice Join balancer pool
    /// @dev Single side join with usdc
    /// @param poolId ID of the balancer pool
    /// @param usdcAmount the amount of usdc to deposit
    function _joinPool(bytes32 poolId, uint usdcAmount) internal {

        (IERC20[] memory tokens, , ) = IBalancerVault.getPoolTokens(poolId);
        uint256[] memory maxAmountsIn = new uint256[](tokens.length);

        maxAmountsIn[0] = usdcAmount;

        bytes memory userData = "Temp"; 

        ///TODO: need to encode type of join to user data

        IBalancerVault.JoinPoolRequest memory request = IBalancerVault.JoinPoolRequest({
            assets: _convertERC20sToAssets(tokens),
            maxAmountsIn: maxAmountsIn,
            userData: userData,
            fromInternalBalance: false
        });

        balancerVault.joinPool(poolId, address(this), msg.sender, request);

    }


    // main contract functions
    // @param N Number of price bands to deposit into (to do autoliquidation-deliquidation of wsteth) if the price of the wsteth collateral goes too low
    function invest(uint256 _wstETHAmount, uint256 _debtAmount, uint256 _N) external {
        
        // Opens a position on crvUSD if no loan already
        if (!crvUSDController.loan_exists(address(this))){
        
        _depositAndCreateLoan(_wstETHAmount, _debtAmount, _N);

        }

        // Note this address is an owner of a crvUSD CDP
        // now we assume that we already have a CDP
        // But there also should be a case when we create a new one

        crvUSDController.add_collateral(_debtAmount, address(this));

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
        uint amounts = [_debtAmount,0];
        uint usdcAmount = crvUSDUSDCPool.exchange({ sold_token_id: 0, bought_token_id: 2, amount: amounts[0], min_output_amount: min_output_amount });

        // Provide liquidity to the D2D/USDC Pool on Balancer
        bytes32 _poolId = 0x27c9f71cc31464b906e0006d4fcbc8900f48f15f00020000000000000000010f;
        _joinPool(poolId, usdcAmount);

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
