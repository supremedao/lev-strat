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
import "./Periphery/BalancerUtils.sol";
import "./Periphery/AuraUtils.sol";
import "./Periphery/CurveUtils.sol";

contract LeverageStrategy is BalancerUtils, AuraUtils, CurveUtils, AccessControl {
    // State variables
    uint256 internal TokenIndex;

    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");
    bytes32 public constant CONTROLLER_ROLE = keccak256("CONTROLLER_ROLE");

    uint256 public crvUSDBorrowed; // Total crvusd borrowed
    uint256 public totalBalancerLPTokens; // Total balancer LP tokens the
    uint256 public totalStakedInAura; // Total balancer LP tokens staked in aura for the user

    // mainnet addresses
    address public treasury; // recieves a fraction of yield
    
    // pools addresses

    // TODO:
    // DAO should be able to change pool parameters and tokens
    // NOTE: maybe we should an updateble strategy struct
    // fix: DAO should only be able to change parameters but not tokens, because switching token will impatc existing tokens
    // if DAO wants to use other token, then deploy a new startegy

    // Events
    // Add relevant events to log important contract actions/events

    /// Constructor
    /// @param _dao is the treasury to withdraw too
    /// @param _controller is the address of the strategy controller
    /// @param _keeper is the address of the power pool keeper
    constructor(address _dao, address _controller, address _keeper, bytes32 _poolId) BalancerUtils(_poolId) {
        treasury = _dao;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(CONTROLLER_ROLE, _controller);
        _grantRole(KEEPER_ROLE, _keeper);
    }

    //================================================EXTERNAL FUNCTIONS===============================================//

    // only DAO can initialize
    // fix: use it directly inside the constructor
    function initializeContracts(
        address _balancerVault,
        address _crvUSD,
        address _crvUSDController,
        address _crvUSDUSDCPool,
        address _wstETH,
        address _USDC,
        address _D2D,
        uint256 _N
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        crvUSDController = IcrvUSDController(_crvUSDController);
        crvUSDUSDCPool = IcrvUSDUSDCPool(_crvUSDUSDCPool);
        N = _N;
    }

    function setTokenIndex(uint256 _TokenIndex) external onlyRole(DEFAULT_ADMIN_ROLE) {
        TokenIndex = _TokenIndex;
    }

    function strategyHealth() external view returns (int256) {
        return crvUSDController.health(address(this), false);
    }

    // main contract functions
    // @param N Number of price bands to deposit into (to do autoliquidation-deliquidation of wsteth) if the price of the wsteth collateral goes too low
    function invest(uint256 _wstETHAmount, uint256 _debtAmount, uint256 _bptAmountOut)
        external
        // fix: why only controller can only invest, anyone should be able to invest
        // fix: we need to keep track of how much a user have invested give and out shares
        onlyRole(CONTROLLER_ROLE)
    {
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
        _joinPool(USDC.balanceOf(address(this)), D2D.balanceOf(address(this)), _bptAmountOut);
        // Stake LP tokens on Aura Finance
        _depositAllAura();
    }

    // fix: how would wstETH end up in this contract?
    // fix: do not allow this operation, to keep track of who invested how much, 
    //  we should only allow to invest directly
    function investFromKeeper(uint256 _bptAmountOut) external onlyRole(KEEPER_ROLE) {
        uint256 amountInStrategy = wstETH.balanceOf(address(this));

        uint256 maxBorrowable = crvUSDController.max_borrowable(amountInStrategy, N); //Should the keeper always borrow max or some %
        // Opens a position on crvUSD if no loan already
        // Note this address is an owner of a crvUSD CDP
        // in the usual case we already have a CDP
        // But there also should be a case when we create a new one
        if (!crvUSDController.loan_exists(address(this))) {
            _depositAndCreateLoan(amountInStrategy, maxBorrowable);
        } else {
            _borrowMore(amountInStrategy, maxBorrowable);
        }

        _exchangeCRVUSDtoUSDC(maxBorrowable);
        // Provide liquidity to the D2D/USDC Pool on Balancer
        _joinPool(maxBorrowable, _bptAmountOut, TokenIndex);
        // Stake LP tokens on Aura Finance
        _depositAllAura();
    }

    // fix: unwind position only based on msg.sender share
    // fix: anyone should be able to unwind their position
    function unwindPosition(uint256[] calldata amounts) external onlyRole(CONTROLLER_ROLE) {
        _unstakeAndWithdrawAura(amounts[0]);

        _exitPool(amounts[1], 1, amounts[2]);

        _exchangeUSDCTocrvUSD(amounts[2]);

        _repayCRVUSDLoan(crvUSD.balanceOf(address(this)));
    }

    // fix: rename this to redeemRewardsToMaintainCDP()
    function unwindPositionFromKeeper() external onlyRole(KEEPER_ROLE) {
        _unstakeAllAndWithdrawAura();

        uint256 bptAmount = _tokenToStake().balanceOf(address(this));

        // TODO: Make a setter with onlyRole(CONTROLLER_ROLE) for % value instead of 30

        uint256 percentOfTotalUsdc = (totalUsdcAmount * 30) / 100;

        _exitPool(bptAmount, 1, percentOfTotalUsdc);

        _exchangeUSDCTocrvUSD(USDC.balanceOf(address(this)));

        _repayCRVUSDLoan(crvUSD.balanceOf(address(this)));
    }

    // fix: rename this to reinvestUsingRewards()
    // note: when reinvesting, ensure the accounting of amount invested remains same.
    function swapReward(uint256 balAmount,uint256 auraAmount, uint256 minWethAmountBal,uint256 minWethAmountAura, uint256 deadline)
        external
        onlyRole(CONTROLLER_ROLE)
    {
        _swapRewardBal(balAmount, minWethAmountBal, deadline);
        _swapRewardAura(auraAmount, minWethAmountAura, deadline);
    }

    //================================================INTERNAL FUNCTIONS===============================================//

    function _tokenToStake() internal view virtual override returns(IERC20) {
        return D2D_USDC_BPT;
    }
}
