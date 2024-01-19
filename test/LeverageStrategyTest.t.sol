pragma solidity ^0.8.0;

import {BaseLeverageStrategyTest} from "./utils/BaseLeverageStrategyTest.sol";
import {console2} from "forge-std/console2.sol";
import {IBasicRewards} from "../contracts/interfaces/IBasicRewards.sol";

contract LeverageStrategyTest is BaseLeverageStrategyTest {
    function setUp() public {
        _deployContracts();
    }

    function testInvest() public subtest {
        // Wsteth gets deposited into vault
        deal(address(wstETH), vault4626, wstEthToAcc);

        levStrat.initialize(investN, dao, controller, powerPool);

        // Make vault msg.sender
        vm.startPrank(vault4626);
        wstETH.approve(address(levStrat), wstInvestAmount);
        levStrat.deposit(wstInvestAmount, vault4626);
        vm.stopPrank();

        deal(address(d2d), address(levStrat), 1000e18);

        vm.prank(controller);

        levStrat.invest(debtAmount, bptExpected);
        assertGt(levStrat.balanceOf(vault4626), 0);

        uint256 aft = AuraLPVault.balanceOf(address(levStrat));
        console2.log("bal aft", aft);
        assertGt(aft, 0);
    }

    function testDepositAndInvest() public subtest {
        // Wsteth gets deposited into vault
        deal(address(wstETH), alice, wstEthToAcc);
        deal(address(wstETH), bob, wstEthToAcc);

        levStrat.initialize(investN, dao, controller, powerPool);

        uint256 vsbefore = levStrat.balanceOf(alice);
        assertEq(vsbefore, 0);
        uint256 vsBobbefore = levStrat.balanceOf(bob);
        assertEq(vsBobbefore, 0);

        // Make vault msg.sender
        vm.startPrank(alice);
        wstETH.approve(address(levStrat), wstInvestAmount);
        levStrat.depositAndInvest(wstInvestAmount, alice, debtAmount, bptExpected);
        vm.stopPrank();

        vm.startPrank(bob);
        wstETH.approve(address(levStrat), wstInvestAmount);
        levStrat.depositAndInvest(wstInvestAmount, bob, debtAmount, bptExpected);
        vm.stopPrank();

        uint256 aft = AuraLPVault.balanceOf(address(levStrat));
        uint256 shares = levStrat.totalSupply();
        uint256 vsAft = levStrat.balanceOf(alice);
        uint256 vsBobAft = levStrat.balanceOf(bob);
        console2.log("bal aft", aft);
        assertGt(aft, 0);
        assertLe(shares, aft);
        assertGt(vsAft, vsbefore);
        assertGt(vsBobAft, vsBobbefore);
        assertNotEq(vsBobAft, vsAft);
    }

    function testInvestIfCDPAlreadyExists() public subtest {
        uint256 before = AuraLPVault.balanceOf(address(levStrat));
        console2.log("bal b4", before);

        // Give wsteth tokens to alice's account
        deal(address(wstETH), vault4626, wstEthToAcc);

        wstETH.approve(address(levStrat), maxApprove);

        levStrat.initialize(investN, dao, controller, powerPool);

        // Make vault msg.sender
        vm.startPrank(vault4626);
        wstETH.approve(address(levStrat), wstInvestAmount);
        levStrat.deposit(wstInvestAmount, vault4626);
        vm.stopPrank();

        vm.prank(controller);

        levStrat.invest(debtAmount, bptExpected);
        assertGt(levStrat.balanceOf(vault4626), 0);

        vm.startPrank(vault4626);
        wstETH.approve(address(levStrat), wstInvestAmount);
        levStrat.deposit(wstInvestAmount, vault4626);
        vm.stopPrank();

        vm.prank(controller);

        levStrat.invest(debtAmount, bptExpected);
        assertGt(levStrat.balanceOf(vault4626), 0);

        uint256 aft = AuraLPVault.balanceOf(address(levStrat));
        console2.log("bal aft", aft);
        assertGt(aft, 0);
    }

    function testUnwind() public subtest {
        // Give wsteth tokens to alice's account
        deal(address(wstETH), vault4626, wstEthToAcc);

        levStrat.initialize(investN, dao, controller, powerPool);

        // Make vault msg.sender
        vm.startPrank(vault4626);
        wstETH.approve(address(levStrat), wstInvestAmount);
        levStrat.deposit(wstInvestAmount, vault4626);
        vm.stopPrank();

        vm.prank(controller);

        levStrat.invest(debtAmount, bptExpected);
        assertGt(levStrat.balanceOf(vault4626), 0);

        uint256 debt_before = crvUSDController.debt(address(levStrat));
        console2.log("debt b4", debt_before);

        _pushDebtToRepay(debtToRepay);

        vm.prank(controller);
        levStrat.unwindPosition(amounts[0]);

        uint256 debt_after = crvUSDController.debt(address(levStrat));

        console2.log("debt b4 2nd check", debt_before);

        console2.log("debt aft", debt_after);

        assertGt(debt_before, debt_after);
    }

    function testUnwindFromPowerPool() public subtest {
        // Give wsteth tokens to alice's account
        deal(address(wstETH), vault4626, wstEthToAcc);

        levStrat.initialize(investN, dao, controller, powerPool);

        // Make vault msg.sender
        vm.startPrank(vault4626);
        wstETH.approve(address(levStrat), wstInvestAmount);
        levStrat.deposit(wstInvestAmount, vault4626);
        vm.stopPrank();

        vm.prank(controller);
        levStrat.invest(debtAmount, bptExpected);
        assertGt(levStrat.balanceOf(vault4626), 0);

        uint256 debt_before = crvUSDController.debt(address(levStrat));

        uint256 wstEthBalBefore = wstETH.balanceOf(address(levStrat));
        uint256 ethBalanceBefore = address(levStrat).balance;
        vm.prank(powerPool);
        levStrat.unwindPositionFromKeeper();
        uint256 wstEthBalAfterUnwind = wstETH.balanceOf(address(levStrat));
        uint256 ethBalanceAfterUnwind = address(levStrat).balance;

        uint256 debt_after = crvUSDController.debt(address(levStrat));

        {
            vm.startPrank(address(levStrat));
            uint256 wstETHUsed = crvUSDController.min_collateral(debt_before, levStrat.N());
            uint256 debtCleared = debt_before - debt_after;
            uint256 percentageOfDebtCleared = debtCleared * 100 / debt_before;
            uint256[4] memory userStateBeforeRemove = crvUSDController.user_state(address(levStrat));
            uint256 totalCollateral = userStateBeforeRemove[0];
            uint256 amountOfWstEthToBeRemoved = totalCollateral * percentageOfDebtCleared / 100;
            uint256 withdrawablewstEth = crvUSDController.min_collateral(debtCleared, levStrat.N());
            crvUSDController.remove_collateral(amountOfWstEthToBeRemoved, false);
        }
        uint256 wstEthBalAfterRemove = wstETH.balanceOf(address(levStrat));
        uint256 ethBalanceAfterRemove = address(levStrat).balance;

        assertEq(wstEthBalAfterUnwind, wstEthBalBefore);
        assertEq(ethBalanceAfterUnwind, ethBalanceBefore);
        assertGt(debt_before, debt_after);
    }

    function test_UserWithdraw() public {
        // give tokens to user 1 and user 2
        deal(address(wstETH), alice, wstInvestAmount);
        deal(address(wstETH), bob, wstInvestAmount * 2);
        deal(address(wstETH), team, wstInvestAmount);

        // variables
        uint256 collateralAmount;
        uint256 maxDebtAmount;

        uint256 startingAliceBalance = wstETH.balanceOf(alice);
        uint256 startingBobBalance = wstETH.balanceOf(bob);

        // initialize
        levStrat.initialize(investN, dao, controller, powerPool);

        // team deposit
        vm.startPrank(team);
        wstETH.approve(address(levStrat), wstInvestAmount);
        levStrat.deposit(wstInvestAmount, team);
        vm.stopPrank();

        // invest
        collateralAmount = wstETH.balanceOf(address(levStrat));
        maxDebtAmount = crvUSDController.max_borrowable(collateralAmount, investN);
        vm.prank(controller);
        levStrat.invest(maxDebtAmount, bptExpected);

        // user 1 deposit
        vm.startPrank(alice);
        wstETH.approve(address(levStrat), wstInvestAmount);
        levStrat.deposit(wstInvestAmount, alice);
        vm.stopPrank();

        // invest
        collateralAmount = wstETH.balanceOf(address(levStrat));
        maxDebtAmount = crvUSDController.max_borrowable(collateralAmount, investN);
        vm.prank(controller);
        levStrat.invest(maxDebtAmount, bptExpected);

        // user 2 deposit
        vm.startPrank(bob);
        wstETH.approve(address(levStrat), wstInvestAmount * 2);
        levStrat.deposit(wstInvestAmount * 2, bob);
        vm.stopPrank();

        // invest
        collateralAmount = wstETH.balanceOf(address(levStrat));
        maxDebtAmount = crvUSDController.max_borrowable(collateralAmount, investN);
        vm.prank(controller);
        levStrat.invest(maxDebtAmount, bptExpected);

        uint256 beforeRedeemAliceBalance = wstETH.balanceOf(alice);
        uint256 beforeRedeemBobBalance = wstETH.balanceOf(bob);

        // user 1 withdraw
        uint256 amountOfVaultSharesToWithdraw = levStrat.balanceOf(alice);
        vm.startPrank(alice);
        levStrat.approve(address(levStrat), amountOfVaultSharesToWithdraw);
        levStrat.redeem(amountOfVaultSharesToWithdraw, alice, alice);
        vm.stopPrank();

        // user 2 withdraw
        amountOfVaultSharesToWithdraw = levStrat.balanceOf(bob);
        vm.startPrank(bob);
        levStrat.approve(address(levStrat), amountOfVaultSharesToWithdraw);
        levStrat.redeem(amountOfVaultSharesToWithdraw, bob, bob);
        vm.stopPrank();

        uint256 afterRedeemAliceBalance = wstETH.balanceOf(alice);
        uint256 afterRedeemBobBalance = wstETH.balanceOf(bob);

        // ensure user 1 receives the funds, vault shares are burnt and no funds is wasted
        assertLt(beforeRedeemAliceBalance, afterRedeemAliceBalance);
        assertLt(startingAliceBalance, afterRedeemAliceBalance);
        assertLt(beforeRedeemBobBalance, afterRedeemBobBalance);
        assertGt(startingBobBalance, afterRedeemBobBalance);
    }
}
