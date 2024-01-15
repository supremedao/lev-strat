pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {LeverageStrategy} from "../../contracts/LeverageStrategy.sol";
import {IERC20} from "../../contracts/interfaces/IERC20.sol";
import {IcrvUSDController} from "../../contracts/interfaces/IcrvUSDController.sol";
import {IBalancerVault} from "../../contracts/interfaces/IBalancerVault.sol";
import {IcrvUSDUSDCPool} from "../../contracts/interfaces/IcrvUSDUSDCPool.sol";
import {IAuraBooster} from "../../contracts/interfaces/IAuraBooster.sol";
import {BaseTest} from "./BaseTest.sol";

contract BaseLeverageStrategyTest is BaseTest {
    LeverageStrategy internal levStrat;
    uint256 testNumber;

    uint256 internal ownerPk = 0x123;
    uint256 internal alicePk = 0xa11ce;
    uint256 internal bobPk = 0xb0b;
    uint256 internal daoPk = 0xDa0;
    uint256 internal vault4626Pk = 0x5432;
    uint256 internal powerPoolPk = 0x4565;
    uint256 internal controllerPk = 0x54762;

    address internal owner = vm.addr(ownerPk);
    address internal alice = vm.addr(alicePk);
    address internal bob = vm.addr(bobPk);
    address internal dao = vm.addr(daoPk);
    address internal vault4626 = vm.addr(vault4626Pk);
    address internal powerPool = vm.addr(powerPoolPk);
    address internal controller = vm.addr(controllerPk);

    uint256 maxApprove = 2 ** 256 - 1;
    uint256 wstEthToAcc = 20 * 1e18;
    uint256 wstInvestAmount2 = 1 * 1e18;

    uint256 internal aliceAmount = 7 * 1e18;
    uint256 internal wstApproveAmount = 2 ** 256 - 1;
    uint256 internal wstInvestAmount = 2 * 1e18;
    uint256 internal debtAmount = 100 * 1e18;
    uint256 internal investN = 10;
    uint256 internal bptExpected = 2 * 1e18;

    IERC20 public usdc;
    IERC20 public wstETH;
    IERC20 public crvUSD;
    IERC20 public d2d;
    IERC20 public circle_deployer;
    IERC20 public d2dusdcBPT;
    IERC20 public AuraLPtoken;
    IERC20 public AuraLPVault;
    IcrvUSDController public crvUSDController;
    IBalancerVault public balancerVault;
    IcrvUSDUSDCPool public crvUSDUSDCPool;
    IAuraBooster public AuraBooster;

    uint256[] public amounts;

    uint256 AuraLPtokenExpected = 2000000000000000000;
    uint256 BPTout = 2000000000000000000;
    uint256 minUsdExpected = 40000;
    uint256 debtToRepay = 4000000;

    function _deployContracts() internal {
        levStrat = new LeverageStrategy(
            dao, controller, powerPool, 0x27c9f71cc31464b906e0006d4fcbc8900f48f15f00020000000000000000010f
        );

        levStrat.setTokenIndex(1);

        wstETH = IERC20(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
        usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        crvUSD = IERC20(0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E);
        crvUSDController = IcrvUSDController(0x100dAa78fC509Db39Ef7D04DE0c1ABD299f4C6CE);
        crvUSDUSDCPool = IcrvUSDUSDCPool(0x4DEcE678ceceb27446b35C672dC7d61F30bAD69E);
        // Deployer of USDC
        circle_deployer = IERC20(0xa2327a938Febf5FEC13baCFb16Ae10EcBc4cbDCF);
        balancerVault = IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
        d2dusdcBPT = IERC20(0x27C9f71cC31464B906E0006d4FcBC8900F48f15f);
        AuraBooster = IAuraBooster(0xA57b8d98dAE62B26Ec3bcC4a365338157060B234);
        AuraLPtoken = IERC20(0x2d63DBBb2ab267D4Dac3abf9C55b12f099D35093);
        AuraLPVault = IERC20(0xe39570EF26fB9A562bf26F8c708b7433F65050af);
        d2d = IERC20(0x43D4A3cd90ddD2F8f4f693170C9c8098163502ad);

        vm.label(address(levStrat), "LevStrategy");
        vm.label(alice, "Alice");

        // Amounts = [AuraLPtoken, BPTout, minUSDCExpected, debtToRepay]
        // amounts.push(AuraLPtokenExpected);
        //amounts.push(BPTout);
        //xamounts.push(minUsdExpected);
    }

    function _pushDebtToRepay(uint256 _num) internal {
        // Amounts = [AuraLPtoken, BPTout, minUSDCExpected]
        amounts.push(AuraLPtokenExpected);
        amounts.push(BPTout);
        amounts.push(minUsdExpected);
        amounts.push(_num);
    }
}
