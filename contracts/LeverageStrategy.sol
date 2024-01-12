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
    // State variables
    //address of aura smart contract
    IAuraBooster public auraBooster;
    // address of balancer vault
    // fix: balancer vault is fixed across chains, we can set it as immutable
    IBalancerVault public balancerVault;

    // fix: address of token will not change, we can set it as immutable
    IcrvUSD public crvUSD;

    // fix: address of crvUSD will not change, we can set it as immutable
    IcrvUSDController public crvUSDController;

    IcrvUSDUSDCPool public crvUSDUSDCPool;
    IBasicRewards public Vaults4626;

    // fix: address of token will most likely never change, we can set it as immutable
    IERC20 public wsteth;
    //IERC20 public crvusd;

    // fix: address of token will most likely never change, we can set it as immutable
    IERC20 public usdc;

    // fix: address of token will most likely never change, we can set it as immutable
    IERC20 public d2d;

    // fix: address of token will most likely never change, we can set it as immutable
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
    address public constant token_BAL = 0xba100000625a3754423978a60c9317c58a424e3D;
    address public constant token_AURA = 0xC0c293ce456fF0ED870ADd98a0828Dd4d2903DBF;
    address public constant token_WETH = 0xdFCeA9088c8A88A76FF74892C1457C17dfeef9C1;
    bytes32 public constant pool_BAL_WETH = 0x5c6ee304399dbdb9c8ef030ab642b10820db8f56000200000000000000000014;
    bytes32 public constant pool_AURA_WETH = 0xcfca23ca9ca720b6e98e3eb9b6aa0ffc4a5c08b9000200000000000000000274;
    bytes32 public constant pool_WSTETH_WETH = 0x93d199263632a4ef4bb438f1feb99e57b4b5f0bd0000000000000000000005c2;

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
    constructor(address _dao, address _controller, address _keeper) {
        treasury = _dao;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(CONTROLLER_ROLE, _controller);
        _grantRole(KEEPER_ROLE, _keeper);
    }

    //================================================EXTERNAL FUNCTIONS===============================================//

    // only DAO can initialize
    // fix: use it directly inside the constructor
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

    // fix: remove the setter functions as pool shouldn't be changed after strategy is deployed
    function setPoolId(bytes32 _poolId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        poolId = _poolId;
    }

    // fix: remove the setter functions as pool shouldn't be changed after strategy is deployed
    function setPid(uint256 _pid) external onlyRole(DEFAULT_ADMIN_ROLE) {
        pid = _pid;
    }

    function setTokenIndex(uint256 _TokenIndex) external onlyRole(DEFAULT_ADMIN_ROLE) {
        TokenIndex = _TokenIndex;
    }

    // fix: remove the setter functions as pool shouldn't be changed after strategy is deployed
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
        _joinPool(usdc.balanceOf(address(this)), d2d.balanceOf(address(this)), _bptAmountOut);
        // Stake LP tokens on Aura Finance
        _depositAllAura();
    }

    // fix: how would wstETH end up in this contract?
    // fix: do not allow this operation, to keep track of who invested how much, 
    //  we should only allow to invest directly
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
        Vaults4626.withdrawAllAndUnwrap(true);

        uint256 bptAmount = d2dusdcBPT.balanceOf(address(this));

        // TODO: Make a setter with onlyRole(CONTROLLER_ROLE) for % value instead of 30

        uint256 percentOfTotalUsdc = (totalUsdcAmount * 30) / 100;

        _exitPool(bptAmount, 1, percentOfTotalUsdc);

        _exchangeUSDCTocrvUSD(usdc.balanceOf(address(this)));

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

        balancerVault.exitPool(poolId, address(this), payable(address(this)), request);
    }


    function _swapRewardBal(uint256 balAmount, uint256 minWethAmount, uint256 deadline) internal {
        IERC20(token_BAL).approve(0xBA12222222228d8Ba445958a75a0704d566BF2C8, balAmount);

        IBalancerVault.SingleSwap memory singleSwap = IBalancerVault.SingleSwap({
            poolId: pool_BAL_WETH,
            kind: IBalancerVault.SwapKind.GIVEN_IN,
            assetIn: IAsset(token_BAL),
            assetOut: IAsset(token_WETH),
            amount: balAmount,
            userData: ""
        });

        IBalancerVault.FundManagement memory funds = IBalancerVault.FundManagement({
            sender: address(this),
            fromInternalBalance: false,
            recipient: payable(address(this)),
            toInternalBalance: false
        });

        balancerVault.swap(singleSwap, funds, 1, deadline);
    }

    function _swapRewardAura(uint256 auraAmount, uint256 minWethAmount, uint256 deadline) internal {
        
        IERC20(token_AURA).approve(0xBA12222222228d8Ba445958a75a0704d566BF2C8, auraAmount);

        IBalancerVault.SingleSwap memory singleSwap = IBalancerVault.SingleSwap({
            poolId: pool_AURA_WETH,
            kind: IBalancerVault.SwapKind.GIVEN_IN,
            assetIn: IAsset(token_AURA),
            assetOut: IAsset(token_WETH),
            amount: auraAmount,
            userData: ""
        });

        IBalancerVault.FundManagement memory funds = IBalancerVault.FundManagement({
            sender: address(this),
            fromInternalBalance: false,
            recipient: payable(address(this)),
            toInternalBalance: false
        });

        balancerVault.swap(singleSwap, funds, 1, deadline);
    }

    function _swapRewardToWstEth(uint256 minWethAmount, uint256 deadline) internal {
        
        IERC20(token_WETH).approve(0xBA12222222228d8Ba445958a75a0704d566BF2C8, minWethAmount);

        IBalancerVault.SingleSwap memory singleSwap = IBalancerVault.SingleSwap({
            poolId: pool_WSTETH_WETH,
            kind: IBalancerVault.SwapKind.GIVEN_IN,
            assetIn: IAsset(token_WETH),
            assetOut: IAsset(address(wsteth)),
            amount: minWethAmount,
            userData: ""
        });

        IBalancerVault.FundManagement memory funds = IBalancerVault.FundManagement({
            sender: address(this),
            fromInternalBalance: false,
            recipient: payable(address(this)),
            toInternalBalance: false
        });

        balancerVault.swap(singleSwap, funds, 1, deadline);
    }

    function _exchangeCRVUSDtoUSDC(uint256 _dx) internal {
        require(crvUSD.approve(address(crvUSDUSDCPool), _dx), "Approval failed");

        uint256 expected = crvUSDUSDCPool.get_dy(1, 0, _dx) * 99 / 100;

        crvUSDUSDCPool.exchange(1, 0, _dx, expected, address(this));
        totalUsdcAmount = usdc.balanceOf(address(this));
    }

    function _exchangeUSDCTocrvUSD(uint256 _dx) internal {
        require(usdc.approve(address(crvUSDUSDCPool), _dx), "Approval failed");
        uint256 expected = crvUSDUSDCPool.get_dy(0, 1, _dx) * 99 / 100;
        crvUSDUSDCPool.exchange(0, 1, _dx, expected, address(this));
        totalUsdcAmount = usdc.balanceOf(address(this));
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
