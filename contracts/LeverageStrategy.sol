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


import "@openzeppelin/access/AccessControl.sol";
import "./interfaces/IAuraBooster.sol";
import "./interfaces/IBalancerVault.sol";
import "./interfaces/IcrvUSD.sol";
import "./interfaces/IcrvUSDController.sol";
import "./interfaces/IcrvUSDUSDCPool.sol";
import "./interfaces/IERC20.sol";

contract LeverageStrategy is AccessControl {

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
    IAuraBooster      public auraBooster;
    IBalancerVault    public balancerVault;
    IcrvUSD           public crvUSD;
    IcrvUSDController public crvUSDController;
    IcrvUSDUSDCPool   public crvUSDUSDCPool;

    IERC20            public wsteth;
    IERC20            public crvusd;
    IERC20            public usdc;
    IERC20            public d2d;
    bytes32           public poolId;
    uint              public pid;

    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");
    bytes32 public constant DAO_ROLE = keccak256("DAO_ROLE");

    uint256           public totalwstETHDeposited;

    // mainnet addresses
    address public treasury; // recieves a fraction of yield


    //mappings
    mapping(address => UserInfo) public userInfo;

    // pools addresses

    // TODO:
    // DAO should be able to change pool parameters and tokens
    // NOTE: maybe we should an updateble strategy struct






    // Events
    // Add relevant events to log important contract actions/events

    // Constructor
    constructor(address _dao) {
         treasury = _dao;
         _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
         _grantRole(DAO_ROLE, _dao);
    }


//================================================EXTERNAL FUNCTIONS===============================================//

  // only DAO can initialize


    function initializeContracts(
        address _auraBooster,
        address _balancerVault,
        address _crvUSD,
        address _crvUSDController,
        address _crvUSDUSDCPool,
        address _wstETH,
        address _USDC,
        address _D2D
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        auraBooster = IAuraBooster(_auraBooster);
        balancerVault = IBalancerVault(_balancerVault);
        crvUSD = IcrvUSD(_crvUSD);
        crvUSDController = IcrvUSDController(_crvUSDController);
        crvUSDUSDCPool = IcrvUSDUSDCPool(_crvUSDUSDCPool);
        wsteth = IERC20(_wstETH);
        usdc = IERC20(_USDC);
        d2d = IERC20(_D2D);

    }

    function setPoolId(bytes32 _poolId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        poolId = _poolId;
    }

    function setPid(uint _pid) external onlyRole(DEFAULT_ADMIN_ROLE) {
        pid = _pid;
    }




    // main contract functions
    // @param N Number of price bands to deposit into (to do autoliquidation-deliquidation of wsteth) if the price of the wsteth collateral goes too low
    function invest(uint256 _wstETHAmount, uint256 _debtAmount, uint256 _N) external {
        
        // Opens a position on crvUSD if no loan already
        //if (!crvUSDController.loan_exists(address(this))){
        
        _depositAndCreateLoan(_wstETHAmount, _debtAmount, _N);

        //}

        // Note this address is an owner of a crvUSD CDP
        // now we assume that we already have a CDP
        // But there also should be a case when we create a new one

        //_addCollateral(_wstETHAmount);

        // borrow crvUSD

        // TODO: calculate borrow amount
        // check if there's price in Curve or we should ping Oracle
    
//_borrowMore(_wstETHAmount, _debtAmount);

        // Exchange crvUSD to USDC on Curve

        // TODO: check the actual token id's and transaction generation
        // Note: seems that we have a different interface compared to supremedao/contracts

        // pool crvUSD -> USDCPool
        // For this Pool:
        // token_id 0 = crvUSD
        // token_id 2 = USDCPool
        //uint[] memory amounts = [_debtAmount,0];
        //uint usdcAmount = crvUSDUSDCPool.exchange({ sold_token_id: 0, bought_token_id: 2, amount: amounts[0], min_output_amount: 100000 });
        uint usdcAmount = 100000;
        _exchangeCRVUSDtoUSDC(_debtAmount);


        // Provide liquidity to the D2D/USDC Pool on Balancer
       // _joinPool(usdcAmount);

        // Stake LP tokens on Aura Finance

        //auraBooster.deposit(pid, borrowAmount, true);
    }



//================================================INTERNAL FUNCTIONS===============================================//
    /// @dev This helper function is a fast and cheap way to convert between IERC20[] and IAsset[] types
    function _convertERC20sToAssets(IERC20[] memory tokens) internal pure returns (IAsset[] memory assets) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            assets := tokens
        }
    }

    /// @notice Create a loan position for the strategy, only used if this is the first position created
    /// @param _wstETHAmount the amount of wsteth deposited
    /// @param _debtAmount the amount of crvusd borrowed
    /// @param _N the number of price bins wsteth is deposited into, this is for crvusds soft liquidations
     function _depositAndCreateLoan(uint256 _wstETHAmount, uint256 _debtAmount, uint256 _N) internal {
        require(_wstETHAmount > 0, "Amount should be greater than 0");
        
        require(IERC20(wsteth).transferFrom(msg.sender, address(this), _wstETHAmount), "Transfer failed"); 


        require(IERC20(wsteth).approve(address(crvUSDController), _wstETHAmount), "Approval failed");
        
        // Call create_loan on the controller
        crvUSDController.create_loan(_wstETHAmount, _debtAmount, _N);

        totalwstETHDeposited = totalwstETHDeposited + _wstETHAmount;
        
        // Update the user's info
        UserInfo storage user = userInfo[msg.sender];
        user.wstETHDeposited = user.wstETHDeposited + _wstETHAmount;
        user.crvUSDBorrowed = user.crvUSDBorrowed + _debtAmount;
        user.loanBand = _N;
    }




    /// @notice Add collateral to a loan postion if the poistion is already initialised
    /// @param _wstETHAmount the amount of wsteth deposited
    function _addCollateral(uint256 _wstETHAmount) internal {
        require(_wstETHAmount > 0, "Amount should be greater than 0");
        
        require(IERC20(wsteth).transferFrom(msg.sender, address(this), _wstETHAmount), "Transfer failed"); 

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
        user.wstETHDeposited = user.wstETHDeposited + _wstETHAmount;
        user.crvUSDBorrowed = user.crvUSDBorrowed + _debtAmount;
        
    }


    /// @notice Join balancer pool
    /// @dev Single side join with usdc
    /// @param usdcAmount the amount of usdc to deposit
    function _joinPool(uint usdcAmount) internal {

        (IERC20[] memory tokens, , ) = balancerVault.getPoolTokens(poolId);
        uint256[] memory maxAmountsIn = new uint256[](tokens.length);

        maxAmountsIn[0] = usdcAmount;

        ///@dev User sends an estimated but unknown (computed at run time) quantity of a single token, and receives a precise quantity of BPT.

        bytes memory userData = abi.encode(IBalancerVault.JoinKind.TOKEN_IN_FOR_EXACT_BPT_OUT);

        ///TODO: need to encode type of join to user data

        IBalancerVault.JoinPoolRequest memory request = IBalancerVault.JoinPoolRequest({
            assets: _convertERC20sToAssets(tokens),
            maxAmountsIn: maxAmountsIn,
            userData: userData,
            fromInternalBalance: false
        });

        balancerVault.joinPool(poolId, address(this), msg.sender, request);

    }
     function _claimRewards() external {

        // Claim rewards from Aura

        // TODO: figure out how to pass all the parameters
    

        // exchange for WSTETH

        // Note: there is no BAL/AURA -> WSTETH Pool
        // TODO: check if there is a single transaction on Balancer
        // otherwise do a jumping transaction BAL -> ETH -> WSTETH

        // call _invest

        uint256 investAmount;
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

    function _exchangeCRVUSDtoUSDC(uint256 _dx ) internal {


        //uint256 expected = crvUSDUSDCPool.get_dy(1, 0, _dx)  * 0.99;

        require(crvUSD.approve(address(crvUSDUSDCPool), _dx), "Approval failed");

        uint256 expected = crvUSDUSDCPool.get_dy(1, 0, _dx) * 99 / 100;
        
        crvUSDUSDCPool.exchange(1, 0, _dx, expected,address(this));

    }






}
