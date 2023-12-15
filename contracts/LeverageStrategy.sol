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
import {console2} from "forge-std/console2.sol";

contract LeverageStrategy is AccessControl {
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
    bytes32 public constant CONTROLLER_ROLE = keccak256("CONTROLLER_ROLE");

    uint256 public totalWsthethDeposited; // Total wsteth deposited
    uint256 public crvUSDBorrowed; // Total crvusd borrowed
    uint256 public totalUsdcAmount; // Total usdc  after swapping from crvusd
    uint256 public totalBalancerLPTokens; // Total balancer LP tokens the
    uint256 public totalStakedInAura; // Total balancer LP tokens staked in aura for the user

    // mainnet addresses
    address public treasury; // recieves a fraction of yield

    // pools addresses

    // TODO:
    // DAO should be able to change pool parameters and tokens
    // NOTE: maybe we should an updateble strategy struct

    // Events
    // Add relevant events to log important contract actions/events

    /// Constructor
    /// @param _dao is the treasury to withdraw too
    /// @param _controller is the address of the strategy controller
    /// @param _keeper is the address of the power pool keeper
    constructor(address _dao, address _controller, address _keeper) {
        treasury = _dao;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
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
    function invest(uint256 _wstETHAmount, uint256 _debtAmount, uint256 _bptAmountOut)
        external
        onlyRole(CONTROLLER_ROLE)
    {
        // This check makes sure that the _wstETHAmount specified by the controller is actually available in this contract
        // The strategy does not handle the deposit of funds, the vault takes the deposits and sends it directly to the strategy
        //require(_wstETHAmount <= wsteth.balanceOf(address(this)));
        console2.log("wstETH amount in invest before cdp", wsteth.balanceOf(address(this)));
        // Opens a position on crvUSD if no loan already
        // Note this address is an owner of a crvUSD CDP
        // in the usual case we already have a CDP
        // But there also should be a case when we create a new one
        console2.log("WSTETH BALANCE BEFORE CDP", _wstETHAmount);
        if (!crvUSDController.loan_exists(address(this))) {
            _depositAndCreateLoan(_wstETHAmount, _debtAmount);
        } else {
            //_addCollateral(_wstETHAmount);
            _borrowMore(_wstETHAmount, _debtAmount);
        }

        console2.log("CRVUSD BALANCE AFTER CDP", crvUSD.balanceOf(address(this)));

        _exchangeCRVUSDtoUSDC(_debtAmount);

        console2.log("USDC BALANCE SWAP", usdc.balanceOf(address(this)));

        // Provide liquidity to the D2D/USDC Pool on Balancer
        _joinPool(usdc.balanceOf(address(this)), d2d.balanceOf(address(this)), _bptAmountOut);

        console2.log("D2DUSDC balance after joinPool", d2dusdcBPT.balanceOf(address(this)));

        // Stake LP tokens on Aura Finance
        _depositAllAura();
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
            _borrowMore(amountInStrategy, maxBorrowable);
        }

        _exchangeCRVUSDtoUSDC(maxBorrowable);
        // Provide liquidity to the D2D/USDC Pool on Balancer
        _joinPool(maxBorrowable, _bptAmountOut, TokenIndex);
        // Stake LP tokens on Aura Finance
        _depositAllAura();
    }

    function unwindPosition(uint256[] calldata amounts) external onlyRole(CONTROLLER_ROLE) {
        _unstakeAndWithdrawAura(amounts[0]);

        _exitPool(amounts[1], 1, amounts[2]);

        console2.log("usdc balance of strat in controller unwind", usdc.balanceOf(address(this)));

        // TODO: Change the  values in the uint[] amounts param as in puts for _exchangeUSDCTocrvUSD and _repayCRVUSDLoan
        // currently balanceOf(this contract) is used to make sure the tests pass
        _exchangeUSDCTocrvUSD(amounts[2]);

        _repayCRVUSDLoan(crvUSD.balanceOf(address(this)));
    }

    function unwindPositionFromKeeper() external onlyRole(KEEPER_ROLE) {
        Vaults4626.withdrawAllAndUnwrap(true);

        uint256 bptAmount = d2dusdcBPT.balanceOf(address(this));

        // TODO: Make a setter with onlyRole(CONTROLLER_ROLE) for % value instead of 30

        uint256 percentOfTotalUsdc = (totalUsdcAmount * 30) / 100;

        _exitPool(bptAmount, 1, percentOfTotalUsdc);

        console2.log("usdc balance of strat in keeper unwind", usdc.balanceOf(address(this)));

        _exchangeUSDCTocrvUSD(usdc.balanceOf(address(this)));

        _repayCRVUSDLoan(crvUSD.balanceOf(address(this)));
    }


    function claimRewardsFromController() external {
        console2.log("In claim rewards");
        _claimRewards();
    }

    function claimRewardsFromKeeper() external onlyRole(CONTROLLER_ROLE) {
        _claimRewards();
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

        totalWsthethDeposited = totalWsthethDeposited + _wstETHAmount;
    }

    /// @notice Add collateral to a loan postion if the poistion is already initialised
    /// @param _wstETHAmount the amount of wsteth deposited
    function _addCollateral(uint256 _wstETHAmount) internal {
        require(_wstETHAmount > 0, "Amount should be greater than 0");

        require(IERC20(wsteth).transferFrom(msg.sender, address(this), _wstETHAmount), "Transfer failed");

        require(IERC20(wsteth).approve(address(crvUSDController), _wstETHAmount), "Approval failed");

        crvUSDController.add_collateral(_wstETHAmount, address(this));
        totalWsthethDeposited = totalWsthethDeposited + _wstETHAmount;
    }

    /// @notice Borrow more crvusd,
    /// @param _wstETHAmount the amount of wsteth deposited
    /// @param _debtAmount the amount of crvusd borrowed
    /// @dev We don't need to transferFrom msg.sender anymore as now the wsteth will be directly transferred by the vault
    function _borrowMore(uint256 _wstETHAmount, uint256 _debtAmount) internal {
        require(IERC20(wsteth).approve(address(crvUSDController), _wstETHAmount), "Approval failed");

        crvUSDController.borrow_more(_wstETHAmount, _debtAmount);

        totalWsthethDeposited = totalWsthethDeposited + _wstETHAmount;
    }

    function _repayCRVUSDLoan(uint256 deptToRepay) internal {
        require(crvUSD.approve(address(crvUSDController), deptToRepay), "Approval failed");
        console2.log("crv usd repay loan", deptToRepay);
        crvUSDController.repay(deptToRepay);
    }

    /// @notice Join balancer pool
    /// @dev Single side join with usdc
    /// @param usdcAmount the amount of usdc to deposit
    function _joinPool(uint256 usdcAmount, uint256 d2dAmount, uint256 minBptAmountOut) internal {
        (IERC20[] memory tokens,,) = balancerVault.getPoolTokens(poolId);
        uint256[] memory maxAmountsIn = new uint256[](tokens.length);

        // Set the amounts for D2D and USDC according to their positions in the pool
        maxAmountsIn[0] = d2dAmount; // D2D token amount
        maxAmountsIn[1] = usdcAmount; // USDC token amount

        // Approve the Balancer Vault to withdraw the respective tokens
        require(IERC20(tokens[0]).approve(address(balancerVault), d2dAmount), "D2D Approval failed");
        require(IERC20(tokens[1]).approve(address(balancerVault), usdcAmount), "USDC Approval failed");

        console2.log("d2d balance of strat", IERC20(tokens[0]).balanceOf(address(this)));

        uint256 joinKind = uint256(IBalancerVault.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT);
        bytes memory userData = abi.encode(joinKind, maxAmountsIn, minBptAmountOut);

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

        console2.log("bptAmountIn", bptAmountIn);
        console2.log("exitTokenIndex", exitTokenIndex);
        console2.log("minAmountOut", minAmountOut);

        balancerVault.exitPool(poolId, address(this), payable(address(this)), request);
    }

    function _claimRewards() internal {
        // Claim rewards from Aura
        auraBooster.claimRewards(pid, 0x1249c510e066731FF14422500466A7102603da9e);

        // exchange for WSTETH

        // Note: there is no BAL/AURA -> WSTETH Pool
        // TODO: check if there is a single transaction on Balancer
        // otherwise do a jumping transaction BAL -> ETH -> WSTETH

        // call _invest
    }

    function _exchangeCRVUSDtoUSDC(uint256 _dx) internal {
        require(crvUSD.approve(address(crvUSDUSDCPool), _dx), "Approval failed");

        uint256 expected = crvUSDUSDCPool.get_dy(1, 0, _dx) * 99 / 100;

        crvUSDUSDCPool.exchange(1, 0, _dx, expected, address(this));
        totalUsdcAmount = usdc.balanceOf(address(this));
    }

    function _exchangeUSDCTocrvUSD(uint256 _dx) internal {
        console2.log("USDC TO CRVUSD DX", _dx);
        require(usdc.approve(address(crvUSDUSDCPool), _dx), "Approval failed");
        uint256 expected = crvUSDUSDCPool.get_dy(0, 1, _dx) * 99 / 100;
        crvUSDUSDCPool.exchange(0, 1, _dx, expected, address(this));
        totalUsdcAmount = usdc.balanceOf(address(this));

        console2.log("crvusd balance after exchange", crvUSD.balanceOf(address(this)));
    }

    function _depositAllAura() internal {
        require(d2dusdcBPT.approve(address(auraBooster), d2dusdcBPT.balanceOf(address(this))), "Approval failed");

        console2.log("Deposit aura here", address(auraBooster));
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
        console2.log("withdraw and unwrap from aura", amount);
        Vaults4626.withdrawAndUnwrap(amount, true);
    }
}
