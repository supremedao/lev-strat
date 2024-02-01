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
import {IPool} from "./interfaces/IPool.sol";
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
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title Leverage Strategy Contract
/// @notice This contract is the core of a leverage strategy involving borrowing tokens,
///         creating a CDP (Collateralized Debt Position), and using the borrowed assets to invest 
///         and stake in the Aura pool to generate yield.
/// @dev The contract rebalances upon PowerAgent interaction
contract LeverageStrategy is
    ERC4626,
    ReentrancyGuard,
    BalancerUtils,
    AuraUtils,
    CurveUtils,
    AccessControl,
    LeverageStrategyStorage
{
    using Math for uint256;

    /// @notice Role identifier for the keeper role, responsible for protocol maintenance tasks. Role given to PowerAgent
    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");

    /// @notice Role identifier for the controller role, responsible for high-level protocol management
    bytes32 public constant CONTROLLER_ROLE = keccak256("CONTROLLER_ROLE");

    /// @notice Fixed percentage (scaled by 10^12) used in unwinding positions, set to 30%
    uint256 public constant FIXED_UNWIND_PERCENTAGE = 30 * 10 ** 10;

    /// @notice Constant representing 100%, used for percentage calculations, scaled by 10^12
    uint256 public constant HUNDRED_PERCENT = 10 ** 12;

    // TODO:
    // DAO should be able to change pool parameters and tokens
    // NOTE: maybe we should an updateble strategy struct
    // fix: DAO should only be able to change parameters but not tokens, because switching token will impatc existing tokens
    // if DAO wants to use other token, then deploy a new startegy

    // Events
    // Add relevant events to log important contract actions/events

    /// @notice Constructs the LeverageStrategy contract and initializes key components
    /// @dev Grants the deployer the default admin role and initializes the contract with 
    ///      Balancer pool ID, sets up ERC20 metadata, and establishes the base asset for ERC4626
    /// @param _poolId The unique identifier of the Balancer pool used in the strategy
    constructor(bytes32 _poolId)
        BalancerUtils(_poolId)
        ERC20("Supreme Aura D2D-USDC vault", "sAura-D2D-USD")
        ERC4626(IERC20(address(AURA_VAULT)))
    {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }


    //================================================EXTERNAL FUNCTIONS===============================================//

    /// @notice Initializes the contract with specific parameters and roles after deployment and makes it ready for investing
    /// @dev Can only be called by an account with the DEFAULT_ADMIN_ROLE
    ///      This function sets key contract parameters and assigns roles to specified addresses.
    ///      It should be called immediately after contract deployment.
    /// @param _N A numeric parameter used in the contract's logic (its specific role should be described)
    /// @param _dao The address to be set as the treasury
    /// @param _controller The address to be granted the CONTROLLER_ROLE
    /// @param _keeper The address (poweragent) to be granted the KEEPER_ROLE
    function initialize(uint256 _N, address _dao, address _controller, address _keeper)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        //set the treasury address
        treasury = _dao;
        //set the number of price bands to deposit into
        N = _N;
        //grant the default admin role to the contract deployer
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        //grant the controller role to the given address
        _grantRole(CONTROLLER_ROLE, _controller);
        //grant the keeper role to the given address (poweragent address)
        _grantRole(KEEPER_ROLE, _keeper);
    }

    /// @notice Sets the index of the token to be withdrawn when exiting the pool
    /// @dev Can only be called by an account with the DEFAULT_ADMIN_ROLE
    ///      This function updates the TokenIndex state variable, which determines the specific token 
    ///      to be withdrawn from a pool when executing certain strategies or operations.
    /// @param _TokenIndex The index of the token in the pool to be set for withdrawal operations
    function setTokenIndex(uint256 _TokenIndex) external onlyRole(DEFAULT_ADMIN_ROLE) {
        //set the index of the token to be withdrawn exiting the pool
        TokenIndex = _TokenIndex;
    }

    /// @notice Returns the health of the strategy's Collateralized Debt Position (CDP) on Curve Finance
    /// @dev This function fetches the health metric from the Curve Finance controller
    ///      It provides an assessment of the current state of the CDP associated with this contract.
    /// @return The health of the CDP as an integer value
    function strategyHealth() external view returns (int256) {
        //return the health of the strategy's CDP on Curve Finance
        return crvUSDController.health(address(this), false);
    }

    /// @notice Cancel a deposit before the amount is invested by keeper or controller
    ///         depositor and sender are both same and can be used interchangebly.
    /// @dev deletes a DepositRecord and returns the tokens back to sender
    /// @param _key the key/id of the deposit record
    function cancelDeposit(uint256 _key) external nonReentrant {
        // get the deposit record for the key
        DepositRecord memory deposit = deposits[_key];

        // ensure that the funds deposited are still not used or already cancelled
        if (deposit.state != DepositState.DEPOSITED) {
            revert DepositCancellationNotAllowed();
        }

        // ensure that the msg.sender is either the sender or receiver of the deposit
        if (deposit.depositor != msg.sender && deposit.receiver != msg.sender) {
            revert UnknownExecuter();
        }

        // remove the deposit record
        delete deposits[_key];

        // send relevant wstETH back to the depositor
        _pushwstEth(deposit.depositor, deposit.amount);
        emit DepositCancelled(_key);
    }

    /// @notice Redeems a specified amount of shares for the underlying asset, closes CDP and sends wstETH to the receiver
    /// @dev This function handles the redemption process with checks for maximum redeemable shares and minimum amount out.
    ///      It reverts if the shares to be redeemed exceed the maximum allowed for the owner.
    ///      It also ensures that the actual amount of assets withdrawn is not less than a specified minimum.
    /// @param shares The number of shares to be redeemed
    /// @param receiver The address that will receive the wstETH assets
    /// @param owner The address that owns the shares being redeemed
    /// @param minAmountOut The minimum amount of USDC assets to receive from the exiting the Balancer pool
    /// @return The amount of assets that were redeemed
    function redeemWstEth(uint256 shares, address receiver, address owner, uint256 minAmountOut)
        public
        virtual
        nonReentrant
        returns (uint256)
    {
        uint256 maxShares = maxRedeem(owner);
        if (shares > maxShares) {
            revert ERC4626ExceededMaxRedeem(owner, shares, maxShares);
        }

        uint256 assets = previewRedeem(shares);
        _withdraw(_msgSender(), receiver, owner, assets, shares, minAmountOut);

        return assets;
    }

    /// @notice reverts everytime to ensure no one can use redeem and withdraw functions
    /// @inheritdoc	ERC4626
    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        virtual
        override
        nonReentrant
    {
        // just to ensure no one uses another withdraw function
        revert UseOverLoadedRedeemFunction();
    }

    /// @notice withdraw funds by burning vault shares
    /// @dev Explain to a developer any extra details
    /// @param caller a parameter just like in doxygen (must be followed by parameter name)
    /// @param receiver a parameter just like in doxygen (must be followed by parameter name)
    /// @param owner a parameter just like in doxygen (must be followed by parameter name)
    /// @param assets a parameter just like in doxygen (must be followed by parameter name)
    /// @param shares a parameter just like in doxygen (must be followed by parameter name)
    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares,
        uint256 minAmountOut
    ) internal virtual {
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }


        // calculate percentage of shares to be withdrawn
        // i.e. the percentage of all the assets that this user has claim to
        uint256 percentageToBeWithdrawn = _convertToPercentage(shares, totalSupply());

        // assets location 1 - wstETH in contract - deposits waiting to invest
        // assets location 2 - wstETH as extra collateral (collateral not utilised to create CDP)
        // assets location 3 - wstTH used to borrow
        // funds from assets location 2 and 3 can be withdrawn using unwind and withdraw wstETH

        // This converts the amount of shares to the amount of `AURA` tokens that need to be withdrawn
        uint256 auraPositionToBeClosed = convertToAssets(shares);
        // We calculate the current debt the strategy has
        uint256[4] memory debtBefore = crvUSDController.user_state(address(this));
        // This withdraws the proportion of assets
        // 1) Withdraw BPT from Boosted AURA
        // 2) Withdraw USDC from balancer pool (requires slippage protection)
        // 3) Swap USDC for curveUSD
        // 4) Repay borrow and receive wstETH
        _unwindPosition(AURA_VAULT.balanceOf(address(this)), percentageToBeWithdrawn, minAmountOut);
        // We get the total collateral freed up
        uint256[4] memory debtAfter = crvUSDController.user_state(address(this));
        // At this point, the amount of debt repaid is the amount that the shares represented
        uint256 totalWithdrawableWstETH =  (debtBefore[2] - debtAfter[2]) * 1e18 / curveAMM.price_oracle() ;
        // We remove this amount of collateral from the CurveController
        _removeCollateral(totalWithdrawableWstETH);
        // Now we burn the user's shares 
        _burn(owner, shares);
        // Now we push the withdrawn wstETH to the user
        _pushwstEth(receiver, totalWithdrawableWstETH);

        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    /// @notice Removes the collateral from the controller
    /// @param  withdrawalAmount The amount of wstETH to withdraw
    function _removeCollateral(uint256 withdrawalAmount) internal {
        crvUSDController.remove_collateral(withdrawalAmount, false);
    }

    /// @notice deposit and invest without waiting for keeper to execute it
    /// @notice vault shares are minted to receiver in this same operation
    /// @dev when a user calls this function, their deposit isn't added to deposit record as the deposit is used immediately
    /// @param assets amount of wstETH to be deposited
    /// @param receiver receiver of the vault shares after the wstETH is utilized
    /// @param _bptAmountOut amount of BPT token expected out once liquidity is provided
    function depositAndInvest(uint256 assets, address receiver, uint256 _bptAmountOut)
        public
        virtual
        nonReentrant
        returns (uint256)
    {
        if (assets == 0) {
            revert ZeroDepositNotAllowed();
        }
        uint256 _debtAmount = crvUSDController.max_borrowable(assets, N);
        // calculate shares
        uint256 currentTotalShares = totalSupply();
        // pull funds from the msg.sender
        _pullwstEth(msg.sender, assets);
        uint256 beforeBalance = IERC20(address(AURA_VAULT)).balanceOf(address(this));
        // invest
        _invest(assets, _debtAmount, _bptAmountOut);
        // mint shares to the msg.sender
        uint256 afterbalance = IERC20(address(AURA_VAULT)).balanceOf(address(this));
        uint256 vsAssets = afterbalance - beforeBalance;
        _mintShares(vsAssets, currentTotalShares, beforeBalance, receiver);
    }

    // main contract functions
    // @param N Number of price bands to deposit into (to do autoliquidation-deliquidation of wsteth) if the price of the wsteth collateral goes too low
    /// @notice Invests in the strategy by creating CDP using wstETH, investing in balancer pool
    ///         and staking BPT tokens on aura to generate yield
    /// @dev This function is non-reentrant and can only be called by an account with the CONTROLLER_ROLE
    ///      It computes the total wstETH to be invested by aggregating deposit records and calculates the maximum borrowable amount.
    ///      The function then invests wstETH, and tracks the new Aura vault shares minted as a result.
    ///      Shares of the vault are minted proportionally to the contribution of each deposit record.
    /// @param _bptAmountOut The targeted amount of Balancer Pool Tokens (BPT) to be received from the investment
    function invest(uint256 _bptAmountOut)
        external
        nonReentrant
        onlyRole(CONTROLLER_ROLE)
    {
        // calculate total wstETH by traversing through all the deposit records
        (uint256 wstEthAmount, uint256 startKeyId,) = _computeAndRebalanceDepsoitRecords();
        uint256 _debtAmount = crvUSDController.max_borrowable(wstEthAmount, N);

        uint256 currentShares = totalSupply();
        // get the current balance of the Aura vault shares
        // to be used to determine how many new vault shares were minted
        uint256 beforeBalance = AURA_VAULT.balanceOf(address(this));

        // invest
        _invest(wstEthAmount, _debtAmount, _bptAmountOut);

        // calculate total new shares minted
        // here assets is Aura Vault shares
        uint256 addedAssets = AURA_VAULT.balanceOf(address(this)) - beforeBalance;

        // we mint vault shares propotional to deposits made by receivers of each deposit record that was used
        _mintMultipleShares(startKeyId, currentShares, beforeBalance, addedAssets * HUNDRED_PERCENT / wstEthAmount);
    }

    /// @notice Executes a queued invest from a Keeper
    /// @dev This function is non-reentrant and can only be called by an account with the KEEPER_ROLE
    ///      It computes the total wstETH to be invested by aggregating deposit records and calculates the maximum borrowable amount.
    ///      The function then invests wstETH, and tracks the new Aura vault shares minted as a result.
    ///      Shares of the vault are minted equally to the contributors of each deposit record
    function investFromKeeper() external nonReentrant onlyRole(KEEPER_ROLE) {
        // Queue an invest from Keeper Call
        investQueued.timestamp = uint64(block.timestamp);
        // We store a simulated amount out as a control value
        (uint256 amountOut, ) = simulateJoinPool(USDC_CONTROL_AMOUNT);
        investQueued.minAmountOut = uint192(investQueued.minAmountOut);
    }

    /// @notice Executes a queued invest from a Keeper
    /// @dev Explain to a developer any extra details
    /// @param _bptAmountOut a parameter just like in doxygen (must be followed by parameter name)
    function executeInvestFromKeeper(uint256 _bptAmountOut) external nonReentrant onlyRole(KEEPER_ROLE) {
        // Do not allow queue and execute in same block
        if (investQueued.timestamp == block.timestamp) revert InvalidInvest();

        (uint256 expectedAmountOut, ) = simulateJoinPool(USDC_CONTROL_AMOUNT);
        // 1% slippage
        if (investQueued.minAmountOut > (uint192(expectedAmountOut) * 99 / 100)) {
            // Slippage control out of date, reset so a new call to `investFromKeeper` can happen
            investQueued.timestamp = 0;
        }

        if (investQueued.timestamp != 0) {
            // calculate total wstETH by traversing through all the deposit records
            (uint256 wstEthAmount, uint256 startKeyId,) = _computeAndRebalanceDepsoitRecords();
            uint256 _debtAmount = crvUSDController.max_borrowable(wstEthAmount, N);

            uint256 currentTotalShares = totalSupply();
            // get the current balance of the Aura vault shares
            // to be used to determine how many new vault shares were minted
            uint256 beforeBalance = AURA_VAULT.balanceOf(address(this));

            uint256 maxBorrowable = crvUSDController.max_borrowable(wstEthAmount, N); //Should the keeper always borrow max or some %

            _invest(wstEthAmount, maxBorrowable, _bptAmountOut);

            // calculate total new shares minted
            // here assets is Aura Vault shares
            uint256 addedAssets = AURA_VAULT.balanceOf(address(this)) - beforeBalance;
            // we equally mint vault shares to the receivers of each deposit record that was used
            _mintMultipleShares(startKeyId, currentTotalShares, beforeBalance, addedAssets * HUNDRED_PERCENT / wstEthAmount);
        } else {
            // If timestamp is 0 we do not have an invest queued
            revert InvalidInvest();
        }
    }

    // fix: unwind position only based on msg.sender share
    // fix: anyone should be able to unwind their position
    function unwindPosition(uint256 auraShares, uint256 minAmountOut) external nonReentrant onlyRole(CONTROLLER_ROLE) {
        _unwindPosition(auraShares, HUNDRED_PERCENT, minAmountOut);
    }

    // fix: rename this to redeemRewardsToMaintainCDP()
    function unwindPositionFromKeeper() external nonReentrant onlyRole(KEEPER_ROLE) {
        (,uint256[] memory minAmountsOut) = simulateExitPool(QUERY_CONTROL_AMOUNT);
        // Grab the exit token index
        unwindQueued.minAmountOut = uint192(minAmountsOut[1]);
        unwindQueued.timestamp = uint64(block.timestamp);

    }

    /// @notice Executes a queued unwindFromKeeper
    /// @dev    Can only be called by Keeper
    function executeUnwindFromKeeper() external onlyRole(KEEPER_ROLE) {
        // Cannot queue and execute in same block!
        if (unwindQueued.timestamp == uint64(block.timestamp)) revert InvalidUnwind();

        // Timestamp is cleared after unwind
        if (unwindQueued.timestamp != 0) {
            // Get current quote
            (,uint256[] memory amountsOut) = simulateExitPool(QUERY_CONTROL_AMOUNT);

            // If the new minAmountOut is 1% smaller than the stored amount out then there is too much slippage
            // Note Always use a protected endpoint to submit transactions!
            // Hardcoded slippage
            if (
                // If the quote amounts are the same, slippage hasn't changed
                unwindQueued.minAmountOut == (uint192(amountsOut[1])) ||
                // If the 99% of current quote is better than old quote, slippage is acceptable
                unwindQueued.minAmountOut < (uint192(amountsOut[1]) * 99 / 100)
            ) {
                _unwindPosition(
                    _convertToValue(AURA_VAULT.balanceOf(address(this)), FIXED_UNWIND_PERCENTAGE),
                    FIXED_UNWIND_PERCENTAGE,
                    0
                );
                unwindQueued.timestamp = 0;

            } else {
                // Slippage is too much
                revert InvalidUnwind();
            }

        } else {
            // No unwind if timestamp is `0`
            revert InvalidUnwind();
        }
    }

    /// @notice Internally handles the unwinding of a position by redeeming and converting assets
    /// @dev This function is internal and part of the unwinding logic used by public facing functions.
    ///      It involves multiple steps: unstaking Aura shares, exiting a Balancer pool, and repaying loans.
    ///      The function calculates the amount of Aura shares to unstake based on a percentage,
    ///      exchanges the redeemed assets, and then repays any outstanding loans.
    /// @param _auraShares The total amount of Aura shares involved in the unwind
    /// @param percentageUnwind The percentage of the position to unwind, scaled by 10^12
    /// @param minAmountOut The minimum amount of underlying assets expected to receive from the unwinding
    function _unwindPosition(uint256 _auraShares, uint256 percentageUnwind, uint256 minAmountOut) internal {
        // Get the proportional amount of shares
        uint256 auraSharesToUnStake = _convertToValue(_auraShares, percentageUnwind);
        // Withdraw in order to get BPT tokens back
        _unstakeAndWithdrawAura(auraSharesToUnStake);

        uint256 bptAmount = _tokenToStake().balanceOf(address(this));

        uint256 beforeUsdcBalance = USDC.balanceOf(address(this));
        // Exit the balancer pool to receive USDC
        _exitPool(bptAmount, 1, minAmountOut);
        // Get current curveUSD balance
        uint256 beforeCrvUSDBalance = crvUSD.balanceOf(address(this));
        // Swap USDC to crvUSD
        _exchangeUSDCTocrvUSD(USDC.balanceOf(address(this)) - beforeUsdcBalance);
        // Repay the loan, there should now be excess collateral
        _repayCRVUSDLoan(crvUSD.balanceOf(address(this)) - beforeCrvUSDBalance);
    }

    /// @notice Calculates the percentage representation of a value with respect to a total amount
    /// @dev This function is internal and pure, used for computing the percentage of a part relative to a whole.
    ///      The calculation scales the percentage by a factor of 10^12 (HUNDRED_PERCENT).
    /// @param value The value to be converted into a percentage
    /// @param total The total amount relative to which the percentage is calculated
    /// @return percent The percentage of the value with respect to the total, scaled by 10^12
    function _convertToPercentage(uint256 value, uint256 total) internal pure returns (uint256 percent) {
        return value * HUNDRED_PERCENT / total;
    }

    /// @notice Calculates the absolute value corresponding to a given percentage of a total amount
    /// @dev This internal and pure function computes the value that a specified percentage represents of a total.
    ///      The calculation uses the HUNDRED_PERCENT constant (scaled by 10^12) to handle percentage scaling.
    /// @param total The total amount from which the value is derived
    /// @param percent The percentage of the total amount to be calculated, scaled by 10^12
    /// @return value The calculated value that the percentage represents of the total amount
    function _convertToValue(uint256 total, uint256 percent) internal pure returns (uint256 value) {
        return total * percent / HUNDRED_PERCENT;
    }

    // fix: rename this to reinvestUsingRewards()
    // note: when reinvesting, ensure the accounting of amount invested remains same.
    /// @notice Swaps BAL and AURA rewards for WETH, specifying minimum amounts and deadline
    /// @dev This function is non-reentrant and can only be called by an account with the CONTROLLER_ROLE
    ///      It internally calls separate functions to handle the swapping of BAL to WETH and AURA to WETH.
    ///      The swaps are executed with specified minimum return amounts and a deadline to ensure slippage protection and timely execution.
    /// @param balAmount The amount of BAL tokens to be swapped for WETH
    /// @param auraAmount The amount of AURA tokens to be swapped for WETH
    /// @param minWethAmountBal The minimum amount of WETH expected from swapping BAL
    /// @param minWethAmountAura The minimum amount of WETH expected from swapping AURA
    /// @param deadline The latest timestamp by which the swap must be completed
    function swapReward(
        uint256 balAmount,
        uint256 auraAmount,
        uint256 minWethAmountBal,
        uint256 minWethAmountAura,
        uint256 deadline
    ) external nonReentrant onlyRole(CONTROLLER_ROLE) {
        _swapRewardBal(balAmount, minWethAmountBal, deadline);
        _swapRewardAura(auraAmount, minWethAmountAura, deadline);
    }

    //================================================INTERNAL FUNCTIONS===============================================//

    /// @notice the token to be staked in the strategy
    /// @dev This internal view function returns the specific token that is used for staking in the strategy.
    ///      It overrides a base class implementation and is meant to be customizable in derived contracts.
    /// @return The IERC20 token which is to be staked, represented here by the D2D_USDC_BPT token
    function _tokenToStake() internal view virtual override returns (IERC20) {
        return D2D_USDC_BPT;
    }

    /// @notice Handles the internal investment process using wstETH, debt amount, and targeted BPT amount
    /// @dev This internal function manages the investment workflow including creating or managing loans, 
    ///      exchanging assets, providing liquidity, and staking LP tokens.
    ///      It opens a position on crvUSD if no loan exists or manages an existing one, exchanges crvUSD to USDC,
    ///      and uses the USDC to provide liquidity in the D2D/USDC pool on Balancer, finally staking the LP tokens on Aura Finance.
    ///      Reverts if the investment amount (_wstETHAmount) is zero.
    /// @param _wstETHAmount The amount of wstETH to be used in the investment
    /// @param _debtAmount The amount of debt to be taken on in the investment
    /// @param _bptAmountOut The targeted amount of Balancer Pool Tokens to be received from the liquidity provision
    function _invest(uint256 _wstETHAmount, uint256 _debtAmount, uint256 _bptAmountOut) internal {
        // only invest if _wstETHAmount >
        if (_wstETHAmount == 0) {
            revert ZeroInvestmentNotAllowed();
        }

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
    function _mintShares(uint256 assets, uint256 currentShares, uint256 currentAssets, address to) internal {
        uint256 shares;
        // won't cause DoS or gridlock because the token token will have no minted tokens before the creation
        if (totalSupply() == 0) {
            shares = assets; // 1:1 ratio when supply is zero
        } else {
            shares = _convertToShares(assets, currentShares, currentAssets, Math.Rounding.Floor);
        }
        _mint(to, shares);
    }

    // function _convertToAssets(uint256 newShares, uint256 currentAssets, uint256 currentShares, Math.Rounding rounding)
    //     internal
    //     view
    //     returns (uint256 _assets)
    // {
    //     return newShares.mulDiv(currentAssets + 1, currentShares + 10 ** _decimalsOffset(), rounding);
    // }

    /// @notice Converts an amount of new assets into equivalent shares based on the current state of the contract
    /// @dev This internal view function calculates the number of shares corresponding to a given amount of new assets,
    ///      considering the current total shares and assets in the contract.
    ///      It uses the mulDiv function for multiplication and division, applying the specified rounding method.
    ///      A decimals offset is added to currentShares for precision adjustments.
    /// @param newAssets The amount of new assets to be converted into shares
    /// @param currentShares The current total number of shares in the contract
    /// @param currentAssets The current total assets in the contract
    /// @param rounding The rounding direction to be used in the calculation (up or down)
    /// @return _shares The calculated number of shares equivalent to the new assets
    function _convertToShares(uint256 newAssets, uint256 currentShares, uint256 currentAssets, Math.Rounding rounding)
        internal
        view
        returns (uint256 _shares)
    {
        return newAssets.mulDiv(currentShares + 10 ** _decimalsOffset(), currentAssets + 1, rounding);
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
        if (assets == 0) {
            revert ZeroDepositNotAllowed();
        }
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
        uint256 length = Math.min(depositCounter - lastUsedDepositKey, 200);
        // set the key ID of first deposit record that will be used
        _startKeyId = lastUsedDepositKey + 1;
        // update the last used deposit record key
        lastUsedDepositKey = lastUsedDepositKey + length;

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
    function _mintMultipleShares(uint256 _startKeyId, uint256 currentShares, uint256 currentAssets, uint256 _assets)
        internal
    {
        // loop over the deposit records starting from the start deposit key ID
        for (_startKeyId; _startKeyId <= lastUsedDepositKey; _startKeyId++) {
            // only mint vault shares to deposit records whose funds have been utilised
            if (deposits[_startKeyId].state == DepositState.INVESTED) {
                uint256 contribution = _assets * deposits[_startKeyId].amount / HUNDRED_PERCENT;
                _mintShares(contribution, currentShares, currentAssets, deposits[_startKeyId].receiver);
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
