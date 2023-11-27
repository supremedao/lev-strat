pragma solidity ^0.8.0;

import {BaseLeverageStrategyTest} from "./utils/BaseLeverageStrategyTest.sol";
import {console} from "forge-std/console.sol";

contract LeverageStrategyTest is BaseLeverageStrategyTest {
    function setUp() public {
        _deployContracts();
    }

    function testInvest() public subtest {
        // Give wsteth tokens to alice's account
        deal(address(wstETH), alice, wstEthToAcc);

        levStrat.initializeContracts(
            address(AuraBooster),
            address(balancerVault),
            address(crvUSD),
            address(crvUSDController),
            address(crvUSDUSDCPool),
            address(wstETH),
            address(usdc),
            address(d2d),
            insvestN
        );

        // Make alice msg.sender
        vm.startPrank(alice);
        wstETH.approve(address(levStrat), maxApprove);

        levStrat.invest(wstInvestAmount, debtAmount, bptExpected);
        vm.stopPrank();
        uint256 aft = AuraLPVault.balanceOf(address(levStrat));
        console.log("bal aft", aft);
        assertGt(aft, 0);
    }

    function testInvestIfCDPAlreadyExists() public subtest {
        uint256 before = AuraLPVault.balanceOf(address(levStrat));
        console.log("bal b4", before);

        // Give wsteth tokens to alice's account
        deal(address(wstETH), alice, wstEthToAcc);

        wstETH.approve(address(levStrat), maxApprove);

        levStrat.initializeContracts(
            address(AuraBooster),
            address(balancerVault),
            address(crvUSD),
            address(crvUSDController),
            address(crvUSDUSDCPool),
            address(wstETH),
            address(usdc),
            address(d2d),
            insvestN
        ); //levStrat.initializeContracts(_auraBooster, _balancerVault, _crvUSD, _crvUSDController, _crvUSDUSDCPool, _wstETH, _USDC, _D2D, Number_of_deposit_bands);

        // Make alice msg.sender
        vm.startPrank(alice);
        wstETH.approve(address(levStrat), maxApprove);
        levStrat.invest(wstInvestAmount, debtAmount, bptExpected);
        levStrat.invest(wstInvestAmount, debtAmount, bptExpected);
        vm.stopPrank();

        uint256 aft = AuraLPVault.balanceOf(address(levStrat));
        console.log("bal aft", aft);
        assertGt(aft, 0);
    }

    function testUnwind() public subtest {
        // Give wsteth tokens to alice's account
        deal(address(wstETH), alice, wstEthToAcc);

        levStrat.initializeContracts(
            address(AuraBooster),
            address(balancerVault),
            address(crvUSD),
            address(crvUSDController),
            address(crvUSDUSDCPool),
            address(wstETH),
            address(usdc),
            address(d2d),
            insvestN
        );

        // Make alice msg.sender
        vm.startPrank(alice);
        wstETH.approve(address(levStrat), maxApprove);

        levStrat.invest(wstInvestAmount, debtAmount, bptExpected);
        vm.stopPrank();
        //uint256 aft = AuraLPVault.balanceOf(address(levStrat));

        //uint256 aftCRVUSD = crvUSD.balanceOf(address(levStrat));
        uint256 debt_before = crvUSDController.debt(address(levStrat));

        _pushDebtToRepay(debt_before);

        levStrat.unwindPosition(amounts);

        uint256 debt_after = crvUSDController.debt(address(levStrat));

        console.log("debt aft", debt_after);

        assertGt(debt_before, debt_after);


    }
}
