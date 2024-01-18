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
    constructor(bytes32 _poolId)
        BalancerUtils(_poolId)
        ERC20("Supreme Aura D2D-USDC vault", "sAura-D2D-USD")
        ERC4626(IERC20(address(AURA_VAULT)))
    {
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

    /// @notice Cancel a deposit before the amount is invested by keeper or controller
    ///         depositor and sender are both same and can be used interchangebly.
    /// @dev deletes a DepositRecord and returns the tokens back to sender
    /// @param _key the key/id of the deposit record
    function cancelDeposit(uint256 _key) external {
        // get the deposit record for the key
        DepositRecord memory deposit = deposits[_key];

        // ensure that the msg.sender is either the sender or receiver of the deposit
        if (deposit.depositor != msg.sender && deposit.receiver != msg.sender) {
            revert UnknownExecuter();
        }

        // ensure that the funds deposited are still not used or already cancelled
        if (deposit.state != DepositState.DEPOSITED) {
            revert DepositCancellationNotAllowed();
        }

        // remove the deposit record
        delete deposits[_key];

        // send relevant wstETH back to the depositor
        _pushwstEth(deposit.depositor, deposit.amount);
        emit DepositCancelled(_key);
    }

    /// @notice deposit and invest without waiting for keeper to execute it
    /// @notice vault shares are minted to receiver in this same operation
    /// @dev when a user calls this function, their deposit isn't added to deposit record as the deposit is used immediately
    /// @param assets amount of wstETH to be deposited
    /// @param receiver receiver of the vault shares after the wstETH is utilized
    /// @param _debtAmount amount of crvUSD to be borrowed
    /// @param _bptAmountOut amount of BPT token expected out once liquidity is provided
    function depositAndInvest(uint256 assets, address receiver, uint256 _debtAmount, uint256 _bptAmountOut)
        public
        virtual
        returns (uint256)
    {
        // pull funds from the msg.sender
        _pullwstEth(msg.sender, assets);
        uint256 beforeBalance = IERC20(address(AURA_VAULT)).balanceOf(address(this));
        // invest
        _invest(assets, _debtAmount, _bptAmountOut);
        // mint shares to the msg.sender
        uint256 afterbalance = IERC20(address(AURA_VAULT)).balanceOf(address(this));
        uint256 vsAssets = afterbalance - beforeBalance;
        _mintShares(vsAssets, receiver);
    }

    // main contract functions
    // @param N Number of price bands to deposit into (to do autoliquidation-deliquidation of wsteth) if the price of the wsteth collateral goes too low
    function invest(uint256 _debtAmount, uint256 _bptAmountOut)
        external
        // fix: why only controller can only invest, anyone should be able to invest
        // fix: we need to keep track of how much a user have invested give and out shares
        onlyRole(CONTROLLER_ROLE)
    {
        // calculate total wstETH by traversing through all the deposit records
        (uint256 wstEthAmount, uint256 startKeyId, uint256 totalDeposits) = _computeAndRebalanceDepsoitRecords();

        // get the current balance of the Aura vault shares
        // to be used to determine how many new vault shares were minted
        uint256 beforeBalance = AURA_VAULT.balanceOf(address(this));

        // invest
        _invest(wstEthAmount, _debtAmount, _bptAmountOut);

        // calculate total new shares minted
        // here assets is Aura Vault shares
        uint256 addedAssets = AURA_VAULT.balanceOf(address(this)) - beforeBalance;

        // we equally mint vault shares to the receivers of each deposit record that was used
        _mintMultipleShares(startKeyId, addedAssets / totalDeposits);
    }

    // fix: how would wstETH end up in this contract?
    // fix: do not allow this operation, to keep track of who invested how much,
    //  we should only allow to invest directly
    function investFromKeeper(uint256 _bptAmountOut) external onlyRole(KEEPER_ROLE) {
        // calculate total wstETH by traversing through all the deposit records
        (uint256 wstEthAmount, uint256 startKeyId, uint256 totalDeposits) = _computeAndRebalanceDepsoitRecords();

        // get the current balance of the Aura vault shares
        // to be used to determine how many new vault shares were minted
        uint256 beforeBalance = AURA_VAULT.balanceOf(address(this));

        uint256 maxBorrowable = crvUSDController.max_borrowable(wstEthAmount, N); //Should the keeper always borrow max or some %

        _invest(wstEthAmount, maxBorrowable, _bptAmountOut);

        // calculate total new shares minted
        // here assets is Aura Vault shares
        uint256 addedAssets = AURA_VAULT.balanceOf(address(this)) - beforeBalance;
        // we equally mint vault shares to the receivers of each deposit record that was used
        _mintMultipleShares(startKeyId, addedAssets / totalDeposits);
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

    /// @notice mint vault shares to an address
    /// @dev if total supply is zero, 1:1 ratio is used
    /// @param assets amount of assets that was deposited, here assets is the Aura Vault Shares
    /// @param to receiver of the vault shares (Leverage Stratgey Vault Shares)
    function _mintShares(uint256 assets, address to) internal {
        uint256 shares;
        if (totalSupply() == 0) {
            shares = assets; // 1:1 ratio when supply is zero
        } else {
            shares = _convertToShares(assets, Math.Rounding.Floor);
        }
        _mint(to, shares);
    }

    /// @notice create and store a neww deposit record
    /// @param _amount amount of wstETH deposited
    /// @param _depositor depositor of the wstETH
    /// @param _receiver receiver of the vault shares after wstETH is invested successfully
    function _recordDeposit(uint256 _amount, address _depositor, address _receiver)
        internal
        returns (uint256 recordKey)
    {
        uint256 currentKey = ++depositCounter;
        deposits[currentKey].depositor = _depositor;
        deposits[currentKey].amount = _amount;
        deposits[currentKey].receiver = _receiver;
        deposits[currentKey].state = DepositState.DEPOSITED;
        return currentKey;
    }

    /// @notice take wstETH and create a deposit record
    /// @dev overrides inherited method
    /// @notice deposit is a two step process:
    ///       1) User deposits wstETH to the vault and a record of their deposit is stored
    ///       2) Keeper/Controller invokes `invest` which invests the wstETH into aura.
    ///          Upon successful invest, vault shares are minted to receivers
    /// @param caller depositor address
    /// @param receiver receiver of vault shares
    /// @param assets amount of wstETH to be deposited (it's different from Aura Vault Shares)
    function _deposit(address caller, address receiver, uint256 assets, uint256) internal virtual override {
        // add it to deposit and generate a key
        uint256 depositKey = _recordDeposit(assets, caller, receiver);
        _pullwstEth(caller, assets);
        // emit
        emit Deposited(depositKey, assets, caller, receiver);
    }

    /// @notice use transferFrom to pull wstETH from an address
    /// @param from owner of the wstETH
    /// @param value amount of wstETH to be transferred
    function _pullwstEth(address from, uint256 value) internal {
        // pull funds from the msg.sender
        bool transferSuccess = wstETH.transferFrom(from, address(this), value);
        if (!transferSuccess) {
            revert ERC20_TransferFromFailed();
        }
    }

    /// @notice compute total wstETH to be utilised for investment and mark those deposits as invested
    /// @dev vault shares are minted after the tokens are invested
    /// @return _wstEthAmount total wstETH amount to be used
    /// @return _startKeyId the first deposit record whose wstETH haven't been used for investment
    /// @return _totalDeposits total number of deposit records utilised in this invest operation
    function _computeAndRebalanceDepsoitRecords()
        internal
        returns (uint256 _wstEthAmount, uint256 _startKeyId, uint256 _totalDeposits)
    {
        // calculate number of deposit record which needs to be analysed
        uint256 length = depositCounter - lastUsedDepositKey;
        // set the key ID of first deposit record that will be used
        _startKeyId = lastUsedDepositKey + 1;
        // update the last used deposit record key
        lastUsedDepositKey = depositCounter;

        // loop over deposit records
        for (uint256 i; i < length; i++) {
            // only use the deposit record if the deposit is not cancelled
            if (deposits[_startKeyId + i].state == DepositState.DEPOSITED) {
                // increase the count of total genuine deposits to be used
                _totalDeposits++;
                // add the amount of depsoit to total wstETH to be used
                _wstEthAmount += deposits[_startKeyId + i].amount;
                // set the state to invested
                deposits[_startKeyId + i].state = DepositState.INVESTED;
            }
        }
        return (_wstEthAmount, _startKeyId, _totalDeposits);
    }

    /// @notice mint vault shares to receivers of all deposit records that was used for investment in current operation
    /// @param _startKeyId first deposit record from where the mint of vault shares will begin
    /// @param _assets amount of Aura vault shares that were minted per deposit record
    function _mintMultipleShares(uint256 _startKeyId, uint256 _assets) internal {
        // loop over the deposit records starting from the start deposit key ID
        for (_startKeyId; _startKeyId <= lastUsedDepositKey; _startKeyId++) {
            // only mint vault shares to deposit records whose funds have been utilised
            if (deposits[_startKeyId].state == DepositState.INVESTED) {
                _mintShares(_assets, deposits[_startKeyId].receiver);
            }
        }
    }

    /// @notice transfer wstETH to an address
    /// @param to receiver of wstETH
    /// @param value amount of wstETH to be transferred
    function _pushwstEth(address to, uint256 value) internal {
        // pull funds from the msg.sender
        bool transferSuccess = wstETH.transfer(to, value);
        if (!transferSuccess) {
            revert ERC20_TransferFailed();
        }
    }
}
