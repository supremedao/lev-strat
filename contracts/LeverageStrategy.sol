// SPDX-License-Identifier: GPL-3.0-or-later

/*
________                                          ______________________ 
__  ___/___  ____________________________ ___________  __ \__    |_  __ \
_____ \_  / / /__  __ \_  ___/  _ \_  __ `__ \  _ \_  / / /_  /| |  / / /
____/ // /_/ /__  /_/ /  /   /  __/  / / / / /  __/  /_/ /_  ___ / /_/ / 
/____/ \__,_/ _  .___//_/    \___//_/ /_/ /_/\___//_____/ /_/  |_\____/  
              /_/                                                        
*/

pragma solidity 0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC4626, Math} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
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
    /// @dev    Can only be called by an account with the DEFAULT_ADMIN_ROLE
    ///         This function sets key contract parameters and assigns roles to specified addresses.
    ///         It should be called immediately after contract deployment.
    /// @param  _N A numeric parameter used in the contract's logic (its specific role should be described)
    /// @param  _controller The address to be granted the CONTROLLER_ROLE (DAO)
    /// @param  _keeper The address (agent) to be granted the KEEPER_ROLE
    /// @param  _jobOwner The address that calls poweragent execution
    function initialize(
        uint256 _N,
        address _controller,
        address _keeper,
        address _jobOwner
    
    )
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        //set the treasury address
        controller = _controller;
        //set the number of price bands to deposit into
        N = _N;
        //grant the controller role to the given address
        _grantRole(CONTROLLER_ROLE, _controller);
        //grant the keeper role to the given address (poweragent address)
        _grantRole(KEEPER_ROLE, _keeper);
        //grant the job owner role to the given address (it creates jobs in poweragent)
        _grantRole(JOB_OWNER_ROLE, _jobOwner);
        //remove admin to lock double initialization
        _revokeRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }



     /// @notice Checks that the jov is called by job owner address
     /// @dev Only PowerAgent job created by job owner can execute function
    modifier onlyOwnerJob() {
        bytes32 jobKey = _getJobKey();
        (address jobOwner, , , , , ) = AgentContract.getJob(
            jobKey
        );
        if (!hasRole(JOB_OWNER_ROLE, jobOwner)) revert InvalidJobOwner();
        _;
    }


    /// @notice Sets the fee for rewards, determining the profit that gets withdrawn to the DAO
    /// @param  _fee the new value of the fee
    function setFee(uint256 _fee) external onlyRole(CONTROLLER_ROLE){
        if (_fee > MAX_DAO_FEE) {
            revert InvalidFee();
        }
        fee = _fee;
    }

    /// @notice Upgrades the address for the poweragent job owner of the contract
    /// @param  _jobOwner the new caller's address
    function setJobOwner(address _oldJobOwner, address _jobOwner) external onlyRole(CONTROLLER_ROLE){
        revokeRole(JOB_OWNER_ROLE, _oldJobOwner);
        grantRole(JOB_OWNER_ROLE, _jobOwner);
    }


    /// @notice Upgrades the address for the controller of the contract
    /// @param  _newController the new controller's address
    function setController(address _oldController, address _newController) external onlyRole(CONTROLLER_ROLE){
        revokeRole(CONTROLLER_ROLE, _oldController);
        grantRole(CONTROLLER_ROLE, _newController);
    }

    /// @notice Sets the maximal amount of funds that can be deposited into LeverageStrategy
    /// @param  _maxInvestment the new limit for the deposits
    function setMaxInvestment(uint256 _maxInvestment) public onlyRole(CONTROLLER_ROLE){
        if(_maxInvestment < currentDeposits){
            maxInvestment = currentDeposits;
        } else {
            maxInvestment = _maxInvestment;
        }
    }

    /// @notice Returns the health of the strategy's Collateralized Debt Position (CDP) on Curve Finance
    /// @dev    This function fetches the health metric from the Curve Finance controller
    ///         It provides an assessment of the current state of the CDP associated with this contract.
    /// @return The health of the CDP as an integer value
    function strategyHealth() public view returns (int256) {
        //return the health of the strategy's CDP on Curve Finance
        return crvUSDController.health(address(this), false);
    }

    /// @notice Cancel a deposit before the amount is invested by keeper or controller
    ///         depositor and sender are both same and can be used interchangebly.
    /// @dev    deletes a DepositRecord and returns the tokens back to sender
    /// @param  _key the key/id of the deposit record
    function cancelDeposit(uint256 _key) external nonReentrant {
        // get the deposit record for the key
        DepositRecord memory deposit = deposits[_key];

        // ensure that the funds deposited are still not used or already cancelled
        if (deposit.state != DepositState.DEPOSITED || deposit.depositor == address(0)) {
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

    function withdrawToken(address token) external onlyRole(CONTROLLER_ROLE){
        if(token != address(wstETH)) {
            revert InvalidInput();
        }
        ERC20(token).transfer(msg.sender, ERC20(token).balanceOf(address(this)));
    }

    /// @notice Redeems a specified amount of shares for the underlying asset, closes CDP and sends wstETH to the receiver
    /// @dev    This function handles the redemption process with checks for maximum redeemable shares and minimum amount out.
    ///         It reverts if the shares to be redeemed exceed the maximum allowed for the owner.
    ///         It also ensures that the actual amount of assets withdrawn is not less than a specified minimum.
    /// @param  shares The number of shares to be redeemed
    /// @param  receiver The address that will receive the wstETH assets
    /// @param  owner The address that owns the shares being redeemed
    /// @param  minAmountOut The minimum amount of USDC assets to receive from the exiting the Balancer pool
    /// @return The amount of assets that were redeemed
    function redeemWstEth(
        uint256 shares,
        address receiver,
        address owner,
        uint256 minAmountOut
    )
        public

        nonReentrant
        returns (uint256)
    {
        uint256 maxShares = maxRedeem(owner);
        if (shares > maxShares) {
            revert ERC4626ExceededMaxRedeem(owner, shares, maxShares);
        }

        currentDeposits -= currentDeposits * shares / this.totalSupply();

        uint256 assets = previewRedeem(shares);
        _withdraw(msg.sender, receiver, owner, assets, shares, minAmountOut);

        return assets;
    }

    /// @notice Deposit and invest without waiting for keeper to execute it
    /// @notice Vault shares are minted to receiver in this same operation
    /// @dev    When a user calls this function, their deposit isn't added to deposit record as the deposit is used immediately
    /// @param  assets amount of wstETH to be deposited
    /// @param  receiver receiver of the vault shares after the wstETH is utilized
    /// @param  _bptAmountOut amount of BPT token expected out once liquidity is provided
    function depositAndInvest(
        uint256 assets,
        address receiver,
        uint256 _bptAmountOut
    )
        public
        nonReentrant
    {
        if (assets == 0) {
            revert ZeroDepositNotAllowed();
        }
        if (currentDeposits + assets > maxInvestment) {
            revert InvestmentsOverflow();
        }

        uint256 _debtAmount = crvUSDController.max_borrowable(assets, N) * healthBuffer / HUNDRED_PERCENT;
        // calculate shares
        uint256 currentTotalShares = totalSupply();
        // pull funds from the msg.sender
        _pullwstEth(msg.sender, assets);
        uint256 beforeBalance = AURA_VAULT.balanceOf(address(this));
        // invest
        _invest(assets, _debtAmount, _bptAmountOut);
        // mint shares to the msg.sender
        uint256 afterbalance = IERC20(address(AURA_VAULT)).balanceOf(address(this));
        uint256 vsAssets = afterbalance - beforeBalance;
        _mintShares(vsAssets, currentTotalShares, beforeBalance, receiver);
    }

    /// @notice Invests in the strategy by creating CDP using wstETH, investing in balancer pool
    ///         and staking BPT tokens on aura to generate yield
    /// @dev    This function is non-reentrant and can only be called by an account with the CONTROLLER_ROLE
    ///         It computes the total wstETH to be invested by aggregating deposit records and calculates the maximum borrowable amount.
    ///         The function then invests wstETH, and tracks the new Aura vault shares minted as a result.
    ///         Shares of the vault are minted proportionally to the contribution of each deposit record.
    /// @param  _bptAmountOut The targeted amount of Balancer Pool Tokens (BPT) to be received from the investment
    function invest(uint256 _bptAmountOut)
        external
        nonReentrant
        onlyRole(CONTROLLER_ROLE)
    {
        // calculate total wstETH by traversing through all the deposit records
        (uint256 wstEthAmount, uint256 startKeyId,) = _computeAndRebalanceDepositRecords();
        uint256 _debtAmount = crvUSDController.max_borrowable(wstEthAmount, N) * healthBuffer / HUNDRED_PERCENT;
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
        _mintMultipleShares(startKeyId, currentShares, beforeBalance, addedAssets, wstEthAmount);
    }

    /// @notice This function is called by PowerPool and queues an invest call
    /// @dev    To provide a measure of manipulation mitigation this call takes a "snapshot"
    ///         of a control amount of asset, this will be compared in the next call.
    ///         This MUST be paired with a protected endpoint AND randomness with regards
    ///         to the subsequent `executeInvestFromKeeper` call timing
    ///         This function is non-reentrant and can only be called by an account with the KEEPER_ROLE
    ///         It computes the total wstETH to be invested by aggregating deposit records and calculates the maximum borrowable amount.
    ///         The function then invests wstETH, and tracks the new Aura vault shares minted as a result.
    ///         Shares of the vault are minted equally to the contributors of each deposit record
    function investFromKeeper() external nonReentrant onlyRole(KEEPER_ROLE) onlyOwnerJob(){
        // Queue an invest from Keeper Call
        investQueued.timestamp = uint64(block.timestamp);
        // We store a simulated amount out as a control value
        (uint256 amountOut, ) = _simulateJoinPool(USDC_CONTROL_AMOUNT);
        investQueued.minAmountOut = uint192(amountOut);
    }

    /// @notice Executes a queued invest from a Keeper
    /// @dev    Invest from keeper executes the call prepared in the previous transaction. Its goal is to execute investment
    ///         of bunch of deposits.
    /// @param  _bptAmountOut The minimum aount of BPT Tokens expected out
    function executeInvestFromKeeper(uint256 _bptAmountOut, bool isReinvest) external nonReentrant onlyRole(KEEPER_ROLE) onlyOwnerJob(){
        // Do not allow queue and execute in same block
        if (investQueued.timestamp == block.timestamp || investQueued.timestamp == 0) revert InvalidInvest();

        (uint256 expectedAmountOut, ) = _simulateJoinPool(USDC_CONTROL_AMOUNT);
        // 1% slippage
        if (
            investQueued.minAmountOut > (uint192(expectedAmountOut) * 99 / 100) &&
            (investQueued.minAmountOut != expectedAmountOut)
        ) {
            // Slippage control out of date, reset so a new call to `investFromKeeper` can happen
            investQueued.timestamp = 0;
        }

        if (isReinvest) {
            uint256[4] memory debtBefore = crvUSDController.user_state(address(this));
            uint256 maxBorrowable = crvUSDController.max_borrowable(debtBefore[0], N);
            // We borrow without adding collateral
            // The max amount given our current collateral - the amount we already have taken
            _invest(0, maxBorrowable - debtBefore[2], expectedAmountOut);
        } else {
            // calculate total wstETH by traversing through all the deposit records
            (uint256 wstEthAmount, uint256 startKeyId,) = _computeAndRebalanceDepositRecords();
            uint256 currentTotalShares = totalSupply();
            // get the current balance of the Aura vault shares
            // to be used to determine how many new vault shares were minted
            uint256 beforeBalance = AURA_VAULT.balanceOf(address(this));
            // Here the keeper is borrowing only 95% of the max borrowable amount
            uint256 maxBorrowable = crvUSDController.max_borrowable(wstEthAmount * healthBuffer / HUNDRED_PERCENT, N); //Should the keeper always borrow max or some %

            _invest(wstEthAmount, maxBorrowable, _bptAmountOut);

            // calculate total new shares minted
            // here assets is Aura Vault shares
            uint256 addedAssets = AURA_VAULT.balanceOf(address(this)) - beforeBalance;
            // we equally mint vault shares to the receivers of each deposit record that was used
            _mintMultipleShares(startKeyId, currentTotalShares, beforeBalance, addedAssets, wstEthAmount);
        }
    }

    /// @notice Unwind call from the Controller
    /// @dev    Used by the Controller/DAO to manually unwind a specific percentage
    /// @param  auraShares The number of asset to unwind
    /// @param  minAmountOut Slippage protection (w.r.t. BPTToken)
    function unwindPosition(uint256 auraShares, uint256 minAmountOut) external nonReentrant onlyRole(CONTROLLER_ROLE) {
        _unwindPosition(auraShares, HUNDRED_PERCENT, minAmountOut);
    }

    /// @notice Queues an unwind call from the automated keeper
    /// @dev    First part of the two-step unwind process
    function unwindPositionFromKeeper() external nonReentrant onlyRole(KEEPER_ROLE) onlyOwnerJob(){
        (,uint256[] memory minAmountsOut) = _simulateExitPool(QUERY_CONTROL_AMOUNT);
        // Grab the exit token index
        unwindQueued.minAmountOut = uint192(minAmountsOut[1]);
        unwindQueued.timestamp = uint64(block.timestamp);
    }

    /// @notice Executes a queued unwindFromKeeper
    /// @dev    Can only be called by Keeper
    function executeUnwindFromKeeper() external onlyRole(KEEPER_ROLE) onlyOwnerJob(){
        // Cannot queue and execute in same block!
        if (unwindQueued.timestamp == uint64(block.timestamp)) revert InvalidUnwind();

        // Timestamp is cleared after unwind
        if (unwindQueued.timestamp != 0) {
            // Get current quote
            (,uint256[] memory amountsOut) = _simulateExitPool(QUERY_CONTROL_AMOUNT);

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
                    _convertToValue(AURA_VAULT.balanceOf(address(this)), unwindPercentage),
                    unwindPercentage,
                    0
                );
                // We need to set timestamp to 0 so next call can happen
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

    /// @notice Sets the health buffer.
    /// @dev    This ensures that the protocol maintains a healthy colalteral factor
    /// @param  percentage Must be smaller than 10e12
    function setHealthBuffer(uint256 percentage) external onlyRole(CONTROLLER_ROLE) {
        if (percentage > HUNDRED_PERCENT) revert InvalidInput();
        healthBuffer = percentage;
    }

    /// @notice Swaps BAL and AURA rewards for WstETH, specifying minimum amounts and deadline
    /// @dev    This function is non-reentrant and can only be called by an account with the KEEPER_ROLE
    ///         It internally calls separate functions to handle the swapping of BAL to WETH and AURA to WETH.
    ///         Afterwards it calls a function to swap WETH to WstEth.
    ///         The swaps are executed with specified minimum return amounts and a deadline to ensure slippage protection and timely execution.
    /// @param  balAmount The amount of BAL tokens to be swapped for WstETH
    /// @param  auraAmount The amount of AURA tokens to be swapped for WETH
    /// @param  minWethAmountBal The minimum amount of WETH expected from swapping BALCONTROLLER
    /// @param  minWethAmountAura The minimum amount of WETH expected from swapping AURA
    /// @param  deadline The latest timestamp by which the swap must be completed
    function swapReward(
        uint256 balAmount,
        uint256 auraAmount,
        uint256 minWethAmountBal,
        uint256 minWethAmountAura,
        uint256 deadline
    ) external nonReentrant onlyRole(KEEPER_ROLE) onlyOwnerJob() {
        // Preparing fee transfer to the DAO
        uint256 balFees = balAmount * fee / HUNDRED_PERCENT;
        uint256 auraFees = auraAmount * fee / HUNDRED_PERCENT;
        // And reward transfer to reinvest(it will be possible to withdraw it for the investors)
        uint256 balReward = balAmount - balFees;
        uint256 auraReward = auraAmount - auraFees;

        // Transfers of the fees to the DAO
        IERC20(BAL).transfer(controller, balFees);
        IERC20(AURA).transfer(controller, balFees);
        // swaps tokens to WETH
        _swapRewardBal(balReward, minWethAmountBal, deadline);
        _swapRewardAura(auraReward, minWethAmountAura, deadline);

        // swaps WETH to wstETH
        uint256 wstEthBefore = wstETH.balanceOf(address(this));
        _swapRewardToWstEth(minWethAmountBal + minWethAmountAura, deadline);

        // transfers fee to DAO and reinvests remaining fees
        uint256 wstEthAmount = wstETH.balanceOf(address(this)) - wstEthBefore;

        (uint256 amountOut, ) = _simulateJoinPool(USDC_CONTROL_AMOUNT);
        uint256 maxBorrowable = crvUSDController.max_borrowable(wstEthAmount * healthBuffer / HUNDRED_PERCENT, N);
        _invest(wstEthAmount, maxBorrowable, amountOut);
    }

    /// @notice Allows the controller to adjust the percentage to unwind at a time
    /// @param  newPercentage The percentage of assets to unwind at a time, normalized to 1e12
    /// @param  newPercentage The percentage of assets to unwind at a time, normalized to 1e12
    function setUnwindPercentage(uint256 newPercentage) external onlyRole(CONTROLLER_ROLE) {
        if (newPercentage > HUNDRED_PERCENT) revert InvalidInput();
        unwindPercentage = newPercentage;
    }

    //================================================INTERNAL FUNCTIONS===============================================//

    /// @notice job key is received from the incomming transaction
    /// @dev    This call is needed to get the PowerAgent job owner's address
    ///         implemented according to https://github.com/Partituraio/PPAgentSafeModule/blob/dev/contracts/PPSafeAgent.sol
    function _getJobKey() private pure returns (bytes32 jobKey) {
        assembly {
            jobKey := calldataload(sub(calldatasize(), 32))
        }
    }

    /// @notice reverts everytime to ensure no one can use redeem and withdraw functions
    /// @dev    The normal `_withdraw` does not allow user to specify slippage protection
    ///         Given that we are swapping this is a good idea.
    function _withdraw(
        address,
        address,
        address,
        uint256,
        uint256
    )
        internal
        override
        nonReentrant
    {
        // just to ensure no one uses another withdraw function
        revert UseOverLoadedRedeemFunction();
    }

    /// @notice Withdraw funds by burning vault shares
    /// @dev    Unwinds from AURA -> BPT -> CURVE -> sends wstETH to user
    /// @param  caller The caller of this function call
    /// @param  receiver The receiver of the wstETH. Receiver requires allowance.
    /// @param  owner The user whose shares are to be burned
    /// @param  assets The number of assets
    /// @param  shares The number of shares to be withdrawn
    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares,
        uint256 minAmountOut
    ) internal {
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }

        // calculate percentage of shares to be withdrawn
        // i.e. the percentage of all the assets that this user has claim to
        uint256 percentageToBeWithdrawn = _convertToPercentage(shares, totalSupply());

        // assets location 1 - wstETH in contract - deposits waiting to invest
        // assets location 2 - wstETH as extra collateral (collateral not utilised to create CDP)
        // assets location 3 - wstETH used to borrow
        // funds from assets location 2 and 3 can be withdrawn using unwind and withdraw wstETH

        // This withdraws the proportion of assets
        // 1) Withdraw BPT from Boosted AURA
        // 2) Withdraw USDC from balancer pool (requires slippage protection)
        // 3) Swap USDC for curveUSD
        // 4) Repay borrow and receive wstETH
        uint256 auraBalance = AURA_VAULT.balanceOf(address(this));
        if(auraBalance > 0) {
            _unwindPosition(auraBalance, percentageToBeWithdrawn, minAmountOut);
        }
        // We get the total collateral freed up
        uint256[4] memory userState = crvUSDController.user_state(address(this));
        /*
         There is nuance here. The yield is expected to go up. But the health buffer means that there is 
         some part of the assets that's not utilised.
         So we assume that the amount of collateral that the user has claim to is equal to his percentage * collateral provided
         This collateral amount is increased when `swapReward` is called AND the Keeper or controller has reinvested the `wstETH` 
         obtained from the rewards.
         Thus, we can simply take the `percentageToBeWithdrawn` and multiply it by the total collateral provided,
         to find the amount of `totalWithdrawableWstEth 
        */
        uint256 totalWithdrawableWstETH =  userState[0] * percentageToBeWithdrawn / HUNDRED_PERCENT;

        // Now we check if there are any funds in the contract, which were withdrawn to the leverage strategy
        uint256 stratBalance = wstETH.balanceOf(address(this));
        uint256 additionalSum = 0;
        // If there are some additional funds in the strategy, they should be also withdrawn
        if (stratBalance > deposited) {
            additionalSum = (stratBalance - deposited) * percentageToBeWithdrawn / HUNDRED_PERCENT;
        }

        // We remove this amount of collateral from the CurveController
        _removeCollateral(totalWithdrawableWstETH);
        // Now we burn the user's shares 
        _burn(owner, shares);

        // Now we push the withdrawn wstETH to the user
        _pushwstEth(receiver, totalWithdrawableWstETH + additionalSum);

        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    /// @notice Internally handles the unwinding of a position by redeeming and converting assets
    /// @dev    This function is internal and part of the unwinding logic used by public facing functions.
    ///         It involves multiple steps: unstaking Aura shares, exiting a Balancer pool, and repaying loans.
    ///         The function calculates the amount of Aura shares to unstake based on a percentage,
    ///         exchanges the redeemed assets, and then repays any outstanding loans.
    /// @param  _auraShares The total amount of Aura shares involved in the unwind
    /// @param  percentageUnwind The percentage of the position to unwind, scaled by 10^12
    /// @param  minAmountOut The minimum amount of underlying assets expected to receive from the unwinding
    function _unwindPosition(
        uint256 _auraShares,
        uint256 percentageUnwind,
        uint256 minAmountOut
    ) internal {
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
    /// @dev    This function is internal and pure, used for computing the percentage of a part relative to a whole.
    ///         The calculation scales the percentage by a factor of 10^12 (HUNDRED_PERCENT).
    /// @param  value The value to be converted into a percentage
    /// @param  total The total amount relative to which the percentage is calculated
    /// @return percent The percentage of the value with respect to the total, scaled by 10^12
    function _convertToPercentage(uint256 value, uint256 total) internal pure returns (uint256 percent) {
        return value * HUNDRED_PERCENT / total;
    }

    /// @notice Calculates the absolute value corresponding to a given percentage of a total amount
    /// @dev    This internal and pure function computes the value that a specified percentage represents of a total.
    ///         The calculation uses the HUNDRED_PERCENT constant (scaled by 10^12) to handle percentage scaling.
    /// @param  total The total amount from which the value is derived
    /// @param  percent The percentage of the total amount to be calculated, scaled by 10^12
    /// @return value The calculated value that the percentage represents of the total amount
    function _convertToValue(uint256 total, uint256 percent) internal pure returns (uint256 value) {
        return total * percent / HUNDRED_PERCENT;
    }

    /// @notice the token to be staked in the strategy
    /// @dev    This internal view function returns the specific token that is used for staking in the strategy.
    ///         It overrides a base class implementation and is meant to be customizable in derived contracts.
    /// @return The IERC20 token which is to be staked, represented here by the D2D_USDC_BPT token
    function _tokenToStake() internal view override returns (IERC20) {
        return D2D_USDC_BPT;
    }

    /// @notice Handles the internal investment process using wstETH, debt amount, and targeted BPT amount
    /// @dev    This internal function manages the investment workflow including creating or managing loans, 
    ///         exchanging assets, providing liquidity, and staking LP tokens.
    ///         It opens a position on crvUSD if no loan exists or manages an existing one, exchanges crvUSD to USDC,
    ///         and uses the USDC to provide liquidity in the D2D/USDC pool on Balancer, finally staking the LP tokens on Aura Finance.
    ///         Reverts if the investment amount (_wstETHAmount) is zero.
    /// @param _wstETHAmount The amount of wstETH to be used in the investment
    /// @param _debtAmount The amount of debt to be taken on in the investment
    /// @param _bptAmountOut The targeted amount of Balancer Pool Tokens to be received from the liquidity provision
    function _invest(
        uint256 _wstETHAmount,
        uint256 _debtAmount,
        uint256 _bptAmountOut
    ) internal {

        currentDeposits += _wstETHAmount;
        // Opens a position on crvUSD if no loan already
        // Note this address is an owner of a crvUSD CDP
        // in the usual case we already have a CDP
        // But there also should be a case when we create a new one
        if (!crvUSDController.loan_exists(address(this))) {
            _depositAndCreateLoan(_wstETHAmount, _debtAmount);
        } else {
            _borrowMore(_wstETHAmount, _debtAmount);
        }
        _exchangeCRVUSDtoUSDC(_debtAmount);
        // Provide liquidity to the D2D/USDC Pool on Balancer
        _joinPool(USDC.balanceOf(address(this)), D2D.balanceOf(address(this)), _bptAmountOut);
        // Stake LP tokens on Aura Finance
        _depositAllAura();
    }

    /// @notice mint vault shares to an address
    /// @dev    if total supply is zero, 1:1 ratio is used
    /// @param  assets amount of assets that was deposited, here assets is the Aura Vault Shares
    /// @param  to receiver of the vault shares (Leverage Stratgey Vault Shares)
    function _mintShares(
        uint256 assets,
        uint256 currentShares,
        uint256 currentAssets,
        address to
    ) internal {
        uint256 shares;
        // won't cause DoS or gridlock because the token token will have no minted tokens before the creation
        if (totalSupply() == 0) {
            shares = assets; // 1:1 ratio when supply is zero
        } else {
            shares = _convertToShares(assets, currentShares, currentAssets, Math.Rounding.Floor);
        }
        _mint(to, shares);
    }

    /// @notice Converts an amount of new assets into equivalent shares based on the current state of the contract
    /// @dev    This internal view function calculates the number of shares corresponding to a given amount of new assets,
    ///         considering the current total shares and assets in the contract.
    ///         It uses the mulDiv function for multiplication and division, applying the specified rounding method.
    ///         A decimals offset is added to currentShares for precision adjustments.
    /// @param  newAssets The amount of new assets to be converted into shares
    /// @param  currentShares The current total number of shares in the contract
    /// @param  currentAssets The current total assets in the contract
    /// @param  rounding The rounding direction to be used in the calculation (up or down)
    function _convertToShares(
        uint256 newAssets,
        uint256 currentShares,
        uint256 currentAssets,
        Math.Rounding rounding
    )
        internal
        view
        returns (uint256)
    {
        return newAssets.mulDiv(currentShares + 10 ** _decimalsOffset(), currentAssets + 1, rounding);
    }

    /// @notice create and store a neww deposit record
    /// @param  _amount amount of wstETH deposited
    /// @param  _depositor depositor of the wstETH
    /// @param  _receiver receiver of the vault shares after wstETH is invested successfully
    function _recordDeposit(
        uint256 _amount,
        address _depositor,
        address _receiver
    )
        internal
        returns (uint256 recordKey)
    {
        recordKey = ++depositCounter;
        deposits[recordKey].depositor = _depositor;
        deposits[recordKey].amount = _amount;
        deposits[recordKey].receiver = _receiver;
        deposits[recordKey].state = DepositState.DEPOSITED;
    }

    /// @notice Take wstETH and create a deposit record
    /// @dev    Overrides inherited method
    /// @notice Deposit is a two step process:
    ///         1) User deposits wstETH to the vault and a record of their deposit is stored
    ///         2) Keeper/Controller invokes `invest` which invests the wstETH into aura.
    ///         Upon successful invest, vault shares are minted to receivers
    /// @param  caller depositor address
    /// @param  receiver receiver of vault shares
    /// @param  assets amount of wstETH to be deposited (it's different from Aura Vault Shares)
    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256
    ) internal override {
        if (currentDeposits + assets > maxInvestment) {
            revert InvestmentsOverflow();
        }

        deposited += assets;
        if (assets == 0) {
            revert ZeroDepositNotAllowed();
        }
        // add it to deposit and generate a key
        uint256 depositKey = _recordDeposit(assets, caller, receiver);
        _pullwstEth(caller, assets);
        // emit
        emit Deposited(depositKey, assets, caller, receiver);
    }

    /// @notice Use transferFrom to pull wstETH from an address
    /// @param  from Owner of the wstETH
    /// @param  value Amount of wstETH to be transferred
    function _pullwstEth(address from, uint256 value) internal {
        // pull funds from the msg.sender
        bool transferSuccess = wstETH.transferFrom(from, address(this), value);
        if (!transferSuccess) {
            revert ERC20_TransferFromFailed();
        }
    }

    /// @notice Compute total wstETH to be utilised for investment and mark those deposits as invested
    /// @dev    Vault shares are minted after the tokens are invested
    /// @return _wstEthAmount Total wstETH amount to be used
    /// @return _startKeyId the First deposit record whose wstETH haven't been used for investment
    /// @return _totalDeposits Total number of deposit records utilised in this invest operation
    function _computeAndRebalanceDepositRecords()
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
            if (deposits[_startKeyId + i].state == DepositState.DEPOSITED
                    && deposits[_startKeyId + i].depositor != address(0) ) {
                // increase the count of total genuine deposits to be used
                _totalDeposits++;
                // add the amount of depsoit to total wstETH to be used
                _wstEthAmount += deposits[_startKeyId + i].amount;
                // set the state to invested
                deposits[_startKeyId + i].state = DepositState.INVESTED;
            }
        }
        deposited -= _wstEthAmount;
        return (_wstEthAmount, _startKeyId, _totalDeposits);
    }

    /// @notice Mint vault shares to receivers of all deposit records that was used for investment in current operation
    /// @param _startKeyId First deposit record from where the mint of vault shares will begin
    /// @param _assets Amount of Aura vault shares that were minted per deposit record
    function _mintMultipleShares(
        uint256 _startKeyId,
        uint256 currentShares,
        uint256 currentAssets,
        uint256 _assets,
        uint256 wstEthAmount
    )
        internal
    {
        // loop over the deposit records starting from the start deposit key ID
        for (_startKeyId; _startKeyId <= lastUsedDepositKey; _startKeyId++) {
            // only mint vault shares to deposit records whose funds have been utilised
            if (deposits[_startKeyId].state == DepositState.INVESTED) {
                // Is there a loss of precision issue here?
                // We try to determine the number of shares that should be issued based on the proportion of wsteth provided
                uint256 contribution = deposits[_startKeyId].amount * _assets / wstEthAmount;
                _mintShares(contribution, currentShares, currentAssets, deposits[_startKeyId].receiver);
                delete deposits[_startKeyId];
            }
        }
    }

    /// @notice Transfer wstETH to an address
    /// @param  to Receiver of wstETH
    /// @param  value Amount of wstETH to be transferred
    function _pushwstEth(address to, uint256 value) internal {
        // pull funds from the msg.sender
        bool transferSuccess = wstETH.transfer(to, value);
        if (!transferSuccess) {
            revert ERC20_TransferFailed();
        }
    }
}
