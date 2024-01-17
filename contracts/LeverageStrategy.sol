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

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC4626, Math} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IAuraBooster} from "./interfaces/IAuraBooster.sol";
import {IBalancerVault} from "./interfaces/IBalancerVault.sol";
import {IcrvUSD} from "./interfaces/IcrvUSD.sol";
import {IcrvUSDController} from "./interfaces/IcrvUSDController.sol";
import {IcrvUSDUSDCPool} from "./interfaces/IcrvUSDUSDCPool.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IBasicRewards} from "./interfaces/IBasicRewards.sol";
import {BalancerUtils} from "./periphery/BalancerUtils.sol";
import {AuraUtils} from "./periphery/AuraUtils.sol";
import {CurveUtils} from "./periphery/CurveUtils.sol";
import {LeverageStrategyStorage} from "./LeverageStrategyStorage.sol";

contract LeverageStrategy is ERC4626, BalancerUtils, AuraUtils, CurveUtils, AccessControl, LeverageStrategyStorage {
    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");
    bytes32 public constant CONTROLLER_ROLE = keccak256("CONTROLLER_ROLE");

    // TODO:
    // DAO should be able to change pool parameters and tokens
    // NOTE: maybe we should an updateble strategy struct
    // fix: DAO should only be able to change parameters but not tokens, because switching token will impatc existing tokens
    // if DAO wants to use other token, then deploy a new startegy

    // Events
    // Add relevant events to log important contract actions/events

    /// Constructor
    constructor(bytes32 _poolId) BalancerUtils(_poolId) ERC20("Supreme Aura D2D-USDC vault", "sAura-D2D-USD") ERC4626(IERC20(address(AURA_VAULT))) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    //================================================EXTERNAL FUNCTIONS===============================================//

    // only DAO can initialize
    // fix: use it directly inside the constructor
    /// @param _dao is the treasury to withdraw too
    /// @param _controller is the address of the strategy controller
    /// @param _keeper is the address of the power pool keeper
    function initialize(uint256 _N, address _dao, address _controller, address _keeper)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        treasury = _dao;
        N = _N;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(CONTROLLER_ROLE, _controller);
        _grantRole(KEEPER_ROLE, _keeper);
    }

    function setTokenIndex(uint256 _TokenIndex) external onlyRole(DEFAULT_ADMIN_ROLE) {
        TokenIndex = _TokenIndex;
    }

    function strategyHealth() external view returns (int256) {
        return crvUSDController.health(address(this), false);
    }

    function cancelDeposit(uint256 _key) external {
        DepositRecord memory deposit = deposits[_key];
        if(deposit.depositor != msg.sender && deposit.receiver != msg.sender) {
            revert UnknownExecuter();
        }
        if(deposit.state != DepositState.DEPOSITED) {
            revert DepositCancellationNotAllowed();
        }
        delete deposits[_key];
        _pushwstEth(deposit.depositor, deposit.amount);
        emit DepositCancelled(_key);
    }

    // 2) deposit and invest - put money into the vault, mint shares and invest money into aura
    function depositAndInvest(uint256 assets, address receiver, uint256 _wstETHAmount, uint256 _debtAmount, uint256 _bptAmountOut) public virtual returns (uint256) {
        // pull funds from the msg.sender
        _pullwstEth(msg.sender, assets);
        uint256 beforeBalance = IERC20(address(AURA_VAULT)).balanceOf(address(this));
        // invest
        _invest(_wstETHAmount, _debtAmount, _bptAmountOut);
        // mint shares to the msg.sender
        uint256 afterbalance = IERC20(address(AURA_VAULT)).balanceOf(address(this));
        uint256 vsAssets = afterbalance - beforeBalance;
        _mintShares(vsAssets, receiver);
    }

    // main contract functions
    // @param N Number of price bands to deposit into (to do autoliquidation-deliquidation of wsteth) if the price of the wsteth collateral goes too low
    function invest(uint256 _wstETHAmount, uint256 _debtAmount, uint256 _bptAmountOut)
        external
        // fix: why only controller can only invest, anyone should be able to invest
        // fix: we need to keep track of how much a user have invested give and out shares
        onlyRole(CONTROLLER_ROLE)
    {
        _invest(_wstETHAmount, _debtAmount, _bptAmountOut);
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
    function swapReward(
        uint256 balAmount,
        uint256 auraAmount,
        uint256 minWethAmountBal,
        uint256 minWethAmountAura,
        uint256 deadline
    ) external onlyRole(CONTROLLER_ROLE) {
        _swapRewardBal(balAmount, minWethAmountBal, deadline);
        _swapRewardAura(auraAmount, minWethAmountAura, deadline);
    }

    //================================================INTERNAL FUNCTIONS===============================================//

    function _tokenToStake() internal view virtual override returns (IERC20) {
        return D2D_USDC_BPT;
    }

    function _invest(uint256 _wstETHAmount, uint256 _debtAmount, uint256 _bptAmountOut) internal {
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

    function _mintShares(uint256 assets, address to) internal {
        uint256 shares;
        if(totalSupply() == 0) {
            shares = assets; // 1:1 ratio when supply is zero
        } else {
            shares = _convertToShares(assets, Math.Rounding.Floor);
        }
        _mint(to, shares);
    }

    function _recordDeposit(uint256 _amount, address _depositor, address _receiver) internal returns(uint256 recordKey) {
        uint256 currentKey = ++depositCounter;
        deposits[currentKey].depositor = _depositor;
        deposits[currentKey].amount = _amount;
        deposits[currentKey].receiver = _receiver;
        deposits[currentKey].state = DepositState.DEPOSITED;
        return currentKey;
    }

    // two functions
    // 1) deposit - put money into the vault and mint shares to user
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal virtual override {
        // add it to deposit and generate a key
        uint256 depositKey = _recordDeposit(assets, caller, receiver);
        _pullwstEth(caller, assets);
        // emit
        emit Deposited(depositKey, assets, caller, receiver);
    }

    function _pullwstEth(address from, uint256 value) internal {
        // pull funds from the msg.sender
        bool transferSuccess = wstETH.transferFrom(from, address(this), value);
        if(!transferSuccess) {
            revert ERC20_TransferFromFailed();
        }
    }

    function _pushwstEth(address to, uint256 value) internal {
        // pull funds from the msg.sender
        bool transferSuccess = wstETH.transfer(to, value);
        if(!transferSuccess) {
            revert ERC20_TransferFailed();
        }
    }
}
