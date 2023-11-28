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
import "./interfaces/IBasicRewards.sol";

contract LeverageStrategy is AccessControl {
    //Struct to keep track of the users funds and where they are allocated
    //TODO: see how many of the struct vars actually need the full uint256
    struct UserInfo {
        uint256 wstETHDeposited; // Total wsteth deposited by a user
        uint256 crvUSDBorrowed; // Total crvusd borrowed by a user
        uint256 usdcAmount; // Total usdc of the user after swapping from crvusd
        uint256 balancerLPTokens; // Total balancer LP tokens the user
        uint256 stakedInAura; // Total balancer LP tokens staked in aura for the user
        uint256 totalYieldEarned; // Historical yield for the user, maybe unnecessary
        uint256 loanBand; // The number of price bands in which the users wsteth will be deposited into
    }

    // State variables
    IAuraBooster public auraBooster;
    IBalancerVault public balancerVault;
    IcrvUSD public crvUSD;
    IcrvUSDController public crvUSDController;
    IcrvUSDUSDCPool public crvUSDUSDCPool;
    IBasicRewards public Vaults4626;

    IERC20 public wsteth;
    //IERC20 public crvusd;
    IERC20 public usdc;
    IERC20 public d2d;
    IERC20 public d2dusdcBPT;
    bytes32 public poolId;
    uint256 public pid;
    uint256 internal TokenIndex;
    uint256 internal N; // Number of bands for the crvusd/wseth soft liquidation range

    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");
    bytes32 public constant DAO_ROLE = keccak256("DAO_ROLE");
    bytes32 public constant CONTROLLER_ROLE = keccak256("DAO_ROLE");

    uint256 public totalwstETHDeposited; // Total wsteth deposited 
    uint256 public crvUSDBorrowed;// Total crvusd borrowed 
    uint256 public totalusdcAmount; // Total usdc  after swapping from crvusd
    uint256 public totalbalancerLPTokens; // Total balancer LP tokens the 
    uint256 public totalstakedInAura; // Total balancer LP tokens staked in aura for the user

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
    constructor(address _dao,address _controller, address _keeper) {
        treasury = _dao;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(DAO_ROLE, _dao);
        _grantRole(CONTROLLER_ROLE, _controller);
        _grantRole(KEEPER_ROLE, _keeper);

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
        address _D2D,
        uint256 _N
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        auraBooster = IAuraBooster(_auraBooster);
        balancerVault = IBalancerVault(_balancerVault);
        crvUSD = IcrvUSD(_crvUSD);
        crvUSDController = IcrvUSDController(_crvUSDController);
        crvUSDUSDCPool = IcrvUSDUSDCPool(_crvUSDUSDCPool);
        wsteth = IERC20(_wstETH);
        usdc = IERC20(_USDC);
        d2d = IERC20(_D2D);
        N = _N;
    }

    function setPoolId(bytes32 _poolId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        poolId = _poolId;
    }

    function setPid(uint256 _pid) external onlyRole(DEFAULT_ADMIN_ROLE) {
        pid = _pid;
    }

    function setTokenIndex(uint256 _TokenIndex) external onlyRole(DEFAULT_ADMIN_ROLE) {
        TokenIndex = _TokenIndex;
    }

    function setBPTAddress(address _bptAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        d2dusdcBPT = IERC20(_bptAddress);
    }

    function setVaultAddress(address _vaultAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        Vaults4626 = IBasicRewards(_vaultAddress);
    }

    function strategyHealth() external view returns (int256) {
        return crvUSDController.health(address(this), false);
    }

    // main contract functions
    // @param N Number of price bands to deposit into (to do autoliquidation-deliquidation of wsteth) if the price of the wsteth collateral goes too low
    function invest(uint256 _wstETHAmount, uint256 _debtAmount, uint256 _bptAmountOut) external onlyRole(CONTROLLER_ROLE) {
        require(_wstETHAmount <= wsteth.balanceOf(address(this)));
        // Opens a position on crvUSD if no loan already
        // Note this address is an owner of a crvUSD CDP
        // in the usual case we already have a CDP
        // But there also should be a case when we create a new one
        if (!crvUSDController.loan_exists(address(this))) {
            _depositAndCreateLoan(_wstETHAmount, _debtAmount);
        } else {
            //_addCollateral(_wstETHAmount);
            _borrowMore(_wstETHAmount, _debtAmount);
        }

        _exchangeCRVUSDtoUSDC(_debtAmount);

        // Provide liquidity to the D2D/USDC Pool on Balancer
        _joinPool(_debtAmount, _bptAmountOut, TokenIndex);

        // Stake LP tokens on Aura Finance
        _depositAllAura();
        //auraBooster.deposit(pid, borrowAmount, true);
    }

    function investFromKeeper(uint256 _bptAmountOut) external onlyRole(KEEPER_ROLE) {
        uint256 amountInStrategy = wsteth.balanceOf(address(this));

        uint256 maxBorrowable = crvUSDController.max_borrowable(amountInStrategy, N); //Should the keeper always borrow max or some %
        // Opens a position on crvUSD if no loan already
        // Note this address is an owner of a crvUSD CDP
        // in the usual case we already have a CDP
        // But there also should be a case when we create a new one
        if (!crvUSDController.loan_exists(address(this))) {
            _depositAndCreateLoan(amountInStrategy, maxBorrowable);
        } else {
            //_addCollateral(_wstETHAmount);
            _borrowMore(amountInStrategy, maxBorrowable);
        }

        _exchangeCRVUSDtoUSDC(maxBorrowable);

        // Provide liquidity to the D2D/USDC Pool on Balancer
        _joinPool(maxBorrowable, _bptAmountOut, TokenIndex);

        // Stake LP tokens on Aura Finance
        _depositAllAura();
        //auraBooster.deposit(pid, borrowAmount, true);
    }


    function unwindPosition(uint256[] calldata amounts) external onlyRole(CONTROLLER_ROLE) {
        _unstakeAndWithdrawAura(amounts[0]);

        _exitPool(amounts[1], 0, amounts[2]);

        _exchangeUSDCTocrvUSD(amounts[2]);

        _repayCRVUSDLoan(amounts[3]);
    }

    function unwindPositionFromKeeper() external onlyRole(KEEPER_ROLE) {

        Vaults4626.withdrawAllAndUnwrap(true);

        uint bptAmount = d2dusdcBPT.balanceOf(address(this));

        _exitPool(bptAmount, 0, totalusdcAmount/2);
 
        _exchangeUSDCTocrvUSD(totalusdcAmount/2);

        _repayCRVUSDLoan(crvUSD.balanceOf(address(this)));
    }

    function claimStrategyRewards() external returns (uint256) {
        uint rewards = Vaults4626.rewards(address(this));
        _claimRewards();
        return rewards;

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
    function _depositAndCreateLoan(uint256 _wstETHAmount, uint256 _debtAmount) internal {
        require(_wstETHAmount > 0, "Amount should be greater than 0");

        //require(IERC20(wsteth).transferFrom(msg.sender, address(this), _wstETHAmount), "Transfer failed");

        require(IERC20(wsteth).approve(address(crvUSDController), _wstETHAmount), "Approval failed");

        // Call create_loan on the controller
        crvUSDController.create_loan(_wstETHAmount, _debtAmount, N);

        totalwstETHDeposited = totalwstETHDeposited + _wstETHAmount;

    }

    /// @notice Add collateral to a loan postion if the poistion is already initialised
    /// @param _wstETHAmount the amount of wsteth deposited
    function _addCollateral(uint256 _wstETHAmount) internal {
        require(_wstETHAmount > 0, "Amount should be greater than 0");

        require(IERC20(wsteth).transferFrom(msg.sender, address(this), _wstETHAmount), "Transfer failed");

        require(IERC20(wsteth).approve(address(crvUSDController), _wstETHAmount), "Approval failed");

        crvUSDController.add_collateral(_wstETHAmount, address(this));
        totalwstETHDeposited = totalwstETHDeposited + _wstETHAmount;
    }

    /// @notice Borrow more crvusd,
    /// @param _wstETHAmount the amount of wsteth deposited
    /// @param _debtAmount the amount of crvusd borrowed
    function _borrowMore(uint256 _wstETHAmount, uint256 _debtAmount) internal {
        // require(IERC20(wsteth).transferFrom(msg.sender, address(this), _wstETHAmount), "Transfer failed");

        require(IERC20(wsteth).approve(address(crvUSDController), _wstETHAmount), "Approval failed");

        crvUSDController.borrow_more(_wstETHAmount, _debtAmount);

        totalwstETHDeposited = totalwstETHDeposited + _wstETHAmount;


    }

    function _repayCRVUSDLoan(uint256 deptToRepay) internal {
        require(crvUSD.approve(address(crvUSDController), deptToRepay), "Approval failed");

        crvUSDController.repay(deptToRepay);
    }

    /// @notice Join balancer pool
    /// @dev Single side join with usdc
    /// @param usdcAmount the amount of usdc to deposit
    function _joinPool(uint256 usdcAmount, uint256 bptAmountOut, uint256 enterTokenIndex) internal {
        (IERC20[] memory tokens,,) = balancerVault.getPoolTokens(poolId);
        uint256[] memory maxAmountsIn = new uint256[](tokens.length);
        require(IERC20(usdc).approve(address(balancerVault), usdcAmount), "Approval failed");

        maxAmountsIn[1] = IERC20(usdc).balanceOf(address(this));

        ///@dev User sends an estimated but unknown (computed at run time) quantity of a single token, and receives a precise quantity of BPT.
        uint256 joinKind = uint256(IBalancerVault.JoinKind.TOKEN_IN_FOR_EXACT_BPT_OUT);
        bytes memory userData = abi.encode(joinKind, bptAmountOut, enterTokenIndex);

        ///TODO: need to encode type of join to user data

        IBalancerVault.JoinPoolRequest memory request = IBalancerVault.JoinPoolRequest({
            assets: _convertERC20sToAssets(tokens),
            maxAmountsIn: maxAmountsIn,
            userData: userData,
            fromInternalBalance: false
        });

        balancerVault.joinPool(poolId, address(this), address(this), request);
    }

    function _exitPool(uint256 bptAmountIn, uint256 exitTokenIndex, uint256 minAmountOut) internal {
        (IERC20[] memory tokens,,) = balancerVault.getPoolTokens(poolId);
        uint256[] memory minAmountsOut = new uint256[](tokens.length);
        minAmountsOut[exitTokenIndex] = minAmountOut;

        // Define the exit kind
        uint256 exitKind = uint256(IBalancerVault.ExitKind.EXACT_BPT_IN_FOR_ONE_TOKEN_OUT);
        bytes memory userData = abi.encode(exitKind, bptAmountIn, exitTokenIndex);

        IBalancerVault.ExitPoolRequest memory request = IBalancerVault.ExitPoolRequest({
            assets: _convertERC20sToAssets(tokens),
            minAmountsOut: minAmountsOut,
            userData: userData,
            toInternalBalance: false
        });

        balancerVault.exitPool(poolId, address(this), payable(address(this)), request);
    }

    function _claimRewards() internal  {

        if (Vaults4626.rewards(address(this)) > 0 ){
            Vaults4626.getReward();
        }

    }

    function _exchangeCRVUSDtoUSDC(uint256 _dx) internal {
        require(crvUSD.approve(address(crvUSDUSDCPool), _dx), "Approval failed");

        uint256 expected = crvUSDUSDCPool.get_dy(1, 0, _dx) * 99 / 100;

        crvUSDUSDCPool.exchange(1, 0, _dx, expected, address(this));
        totalusdcAmount = totalusdcAmount + expected;
    }

    function _exchangeUSDCTocrvUSD(uint256 _dx) internal {
        require(usdc.approve(address(crvUSDUSDCPool), _dx), "Approval failed");
        uint256 expected = crvUSDUSDCPool.get_dy(0, 1, _dx) * 99 / 100;
        crvUSDUSDCPool.exchange(0, 1, _dx, expected, address(this));
        totalusdcAmount = totalusdcAmount - _dx;
    }

    function _depositAllAura() internal {
        require(d2dusdcBPT.approve(address(auraBooster), d2dusdcBPT.balanceOf(address(this))), "Approval failed");
        require(auraBooster.depositAll(pid, true));
    }

    function _depositAura(uint256 ammount) internal {
        require(d2dusdcBPT.approve(address(auraBooster), ammount), "Approval failed");
        require(auraBooster.deposit(pid, ammount, true));
    }

    function _withdrawAllAura() internal {
        auraBooster.withdrawAll(pid);
    }

    function _withdrawAura(uint256 ammount) internal {
        auraBooster.withdraw(pid, ammount);
    }

    function _unstakeAndWithdrawAura(uint256 amount) internal {
        Vaults4626.withdrawAndUnwrap(amount, true);
    }
}
