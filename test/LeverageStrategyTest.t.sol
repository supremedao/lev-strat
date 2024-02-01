pragma solidity ^0.8.0;

import {BaseLeverageStrategyTest} from "./utils/BaseLeverageStrategyTest.sol";
import {console2} from "forge-std/console2.sol";
import {IBasicRewards} from "../contracts/interfaces/IBasicRewards.sol";
import {LeverageStrategyStorage} from "../contracts/LeverageStrategyStorage.sol";

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

        levStrat.invest(bptExpected);
        assertGt(levStrat.balanceOf(vault4626), 0);

        uint256 aft = AuraLPVault.balanceOf(address(levStrat));
        console2.log("bal aft", aft);
        assertGt(aft, 0);
    }

    function testMultipleUsersInvest() public subtest {
        // Wsteth gets deposited into vault
        deal(address(wstETH), vault4626, wstEthToAcc);
        deal(address(wstETH), alice, wstEthToAcc);

        levStrat.initialize(investN, dao, controller, powerPool);

        // Make vault msg.sender
        vm.startPrank(vault4626);
        wstETH.approve(address(levStrat), wstInvestAmount);
        levStrat.deposit(wstInvestAmount, vault4626);
        vm.stopPrank();

        // Make vault msg.sender
        vm.startPrank(alice);
        wstETH.approve(address(levStrat), wstInvestAmount * 2);
        levStrat.deposit(wstInvestAmount * 2, alice);
        vm.stopPrank();

        vm.prank(controller);
        levStrat.invest(bptExpected);
        assertGt(levStrat.balanceOf(vault4626), 0);

        uint256 aliceShares = levStrat.balanceOf(alice);
        uint256 vaultShares = levStrat.balanceOf(vault4626);

        assertEq(aliceShares / 2, vaultShares);

        uint256 aft = AuraLPVault.balanceOf(address(levStrat));
        console2.log("bal aft", aft);
        assertGt(aft, 0);
    }

    function testRevertZeroDeposit() public subtest {
        levStrat.initialize(investN, dao, controller, powerPool);

        // Make vault msg.sender
        vm.startPrank(vault4626);
        vm.expectRevert(LeverageStrategyStorage.ZeroDepositNotAllowed.selector);
        levStrat.deposit(0, vault4626);
        vm.stopPrank();
    }

    function testRevertZeroDepositWhenDepositingAndInvesting() public subtest {
        levStrat.initialize(investN, dao, controller, powerPool);

        // Make vault msg.sender
        vm.startPrank(vault4626);
        vm.expectRevert(LeverageStrategyStorage.ZeroDepositNotAllowed.selector);
        levStrat.depositAndInvest(0, vault4626, 0);
        vm.stopPrank();
    }

    function testRevertZeroInvestment() public subtest {
        levStrat.initialize(investN, dao, controller, powerPool);

        // Make vault msg.sender
        vm.startPrank(controller);
        vm.expectRevert(LeverageStrategyStorage.ZeroDepositNotAllowed.selector);
        levStrat.depositAndInvest(0, address(this), 1);

        vm.expectRevert("Amount should be greater than 0");
        levStrat.invest(bptExpected);
        vm.stopPrank();
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
        levStrat.depositAndInvest(wstInvestAmount, alice, bptExpected);
        vm.stopPrank();

        vm.startPrank(bob);
        wstETH.approve(address(levStrat), wstInvestAmount);
        levStrat.depositAndInvest(wstInvestAmount, bob, bptExpected);
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

        levStrat.invest(bptExpected);
        assertGt(levStrat.balanceOf(vault4626), 0);

        vm.startPrank(vault4626);
        wstETH.approve(address(levStrat), wstInvestAmount);
        levStrat.deposit(wstInvestAmount, vault4626);
        vm.stopPrank();

        vm.prank(controller);

        levStrat.invest(bptExpected);
        assertGt(levStrat.balanceOf(vault4626), 0);

        uint256 aft = AuraLPVault.balanceOf(address(levStrat));
        console2.log("bal aft", aft);
        assertGt(aft, 0);
    }

    function testInvestIfCDPAlreadyExistsWith201Deposits() public subtest {
        uint256 before = AuraLPVault.balanceOf(address(levStrat));
        console2.log("bal b4", before);

        // Give wsteth tokens to alice's account
        deal(address(wstETH), vault4626, wstEthToAcc * 201);

        wstETH.approve(address(levStrat), maxApprove);

        levStrat.initialize(investN, dao, controller, powerPool);

        // Make vault msg.sender
        vm.startPrank(vault4626);
        wstETH.approve(address(levStrat), maxApprove);
        assertEq(levStrat.depositCounter(), 0);
        for (uint256 i; i < 201; i++) {
            levStrat.deposit(wstInvestAmount, vault4626);
        }
        assertEq(levStrat.depositCounter(), 201);
        vm.stopPrank();

        vm.prank(controller);

        levStrat.invest(bptExpected);
        assertEq(levStrat.depositCounter(), levStrat.lastUsedDepositKey() + 1);
        assertGt(levStrat.balanceOf(vault4626), 0);

        // invest again the remaining 1 deposit
        vm.prank(controller);
        levStrat.invest(bptExpected);
        assertEq(levStrat.depositCounter(), levStrat.lastUsedDepositKey());

        uint256 aft = AuraLPVault.balanceOf(address(levStrat));
        console2.log("bal aft", aft);
        assertGt(aft, 0);
    }

    function testInvestFromKeeperIfCDPAlreadyExists() public subtest {
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

        vm.startPrank(powerPool);
        levStrat.investFromKeeper();
        uint256 currentTimestamp = block.timestamp;
        // Simulate the block passing
        vm.warp(currentTimestamp + 12);
        levStrat.executeInvestFromKeeper(1, false);
        assertGt(levStrat.balanceOf(vault4626), 0);

        vm.startPrank(vault4626);
        wstETH.approve(address(levStrat), wstInvestAmount);
        levStrat.deposit(wstInvestAmount, vault4626);
        vm.stopPrank();

        vm.prank(controller);

        levStrat.invest(bptExpected);
        assertGt(levStrat.balanceOf(vault4626), 0);

        uint256 aft = AuraLPVault.balanceOf(address(levStrat));
        console2.log("bal aft", aft);
        assertGt(aft, 0);
    }

    function testInvestFromKeeperIfCDPAlreadyExistsAndCheckHealth() public subtest {
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

        vm.startPrank(powerPool);
        levStrat.investFromKeeper();
        uint256 currentTimestamp = block.timestamp;
        // Simulate the block passing
        vm.warp(currentTimestamp + 12);
        levStrat.executeInvestFromKeeper(1, false);
        assertGt(levStrat.balanceOf(vault4626), 0);

        vm.startPrank(vault4626);
        wstETH.approve(address(levStrat), wstInvestAmount);
        levStrat.deposit(wstInvestAmount, vault4626);
        vm.stopPrank();

        vm.prank(controller);

        levStrat.invest(bptExpected);
        assertGt(levStrat.balanceOf(vault4626), 0);

        int256 health = levStrat.strategyHealth();
        assertGt(health, 0);

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

        levStrat.invest(bptExpected);
        assertGt(levStrat.balanceOf(vault4626), 0);

        uint256 debt_before = crvUSDController.debt(address(levStrat));
        console2.log("debt b4", debt_before);

        _pushDebtToRepay(debtToRepay);

        vm.prank(controller);
        levStrat.unwindPosition(amounts[0], minAmountOut);

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
        levStrat.invest(bptExpected);
        assertGt(levStrat.balanceOf(vault4626), 0);

        uint256 debt_before = crvUSDController.debt(address(levStrat));

        uint256 wstEthBalBefore = wstETH.balanceOf(address(levStrat));
        uint256 ethBalanceBefore = address(levStrat).balance;
        uint256 time = block.timestamp;
        vm.startPrank(powerPool);
        levStrat.unwindPositionFromKeeper();
        vm.warp(time + 12);
        levStrat.executeUnwindFromKeeper();
        vm.stopPrank();

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

    function test_success_UserWithdraw() public {
        // give tokens to user 1 and user 2
        deal(address(wstETH), alice, wstInvestAmount);
        deal(address(wstETH), bob, wstInvestAmount * 2);
        deal(address(wstETH), team, wstInvestAmount * 10);
        deal(address(wstETH), address(101), 1e16);

        uint256 startingAliceBalance = wstETH.balanceOf(alice);
        uint256 startingBobBalance = wstETH.balanceOf(bob);

        // initialize
        levStrat.initialize(investN, dao, controller, powerPool);

        // team deposit
        vm.startPrank(team);
        wstETH.approve(address(levStrat), wstInvestAmount * 10);
        levStrat.deposit(wstInvestAmount * 10, team);
        vm.stopPrank();

        // invest
        vm.prank(controller);
        levStrat.invest(bptExpected);

        // Team sets rates
        vm.startPrank(address(101));
        wstETH.approve(address(levStrat), 1e16);
        levStrat.deposit(1e16, address(101));
        vm.stopPrank();

        // user 1 deposit
        vm.startPrank(alice);
        wstETH.approve(address(levStrat), wstInvestAmount);
        levStrat.deposit(wstInvestAmount, alice);
        vm.stopPrank();

        // invest
        vm.prank(controller);
        levStrat.invest(bptExpected);

        // user 2 deposit
        vm.startPrank(bob);
        wstETH.approve(address(levStrat), wstInvestAmount * 2);
        levStrat.deposit(wstInvestAmount * 2, bob);
        vm.stopPrank();

        // invest
        vm.prank(controller);
        levStrat.invest(bptExpected);

        uint256 beforeRedeemAliceBalance = wstETH.balanceOf(alice);
        uint256 beforeRedeemBobBalance = wstETH.balanceOf(bob);
        console2.log(beforeRedeemAliceBalance);
        console2.log(beforeRedeemBobBalance);

        // user 1 withdraw
        uint256 amountOfVaultSharesToWithdraw = levStrat.balanceOf(alice);
        vm.startPrank(alice);
        levStrat.approve(address(levStrat), amountOfVaultSharesToWithdraw);
        levStrat.redeemWstEth(amountOfVaultSharesToWithdraw, alice, alice, minAmountOut);
        vm.stopPrank();

        // user 2 withdraw
        amountOfVaultSharesToWithdraw = levStrat.balanceOf(bob);
        vm.startPrank(bob);
        levStrat.approve(address(levStrat), amountOfVaultSharesToWithdraw);
        levStrat.redeemWstEth(amountOfVaultSharesToWithdraw, bob, bob, minAmountOut);
        vm.stopPrank();

        amountOfVaultSharesToWithdraw = levStrat.balanceOf(team);
        vm.startPrank(team);
        levStrat.approve(address(levStrat), amountOfVaultSharesToWithdraw);
        levStrat.redeemWstEth(amountOfVaultSharesToWithdraw * 95 / 100, team, team, minAmountOut);
        vm.stopPrank();

        uint256 afterRedeemAliceBalance = wstETH.balanceOf(alice);
        uint256 afterRedeemBobBalance = wstETH.balanceOf(bob);
        uint256 afterRedeemTeamBalance = wstETH.balanceOf(team);

        // ensure user 1 receives the funds, vault shares are burnt and no funds is wasted
        console2.log(afterRedeemAliceBalance);
        console2.log(afterRedeemBobBalance);
        console2.log(afterRedeemTeamBalance);
        assertLt(beforeRedeemAliceBalance, afterRedeemAliceBalance);
        assertLt(beforeRedeemBobBalance, afterRedeemBobBalance);
        assertGt(startingBobBalance, afterRedeemBobBalance);
    }

    function test_UserWithdraw_ExtraChecks() public {
        // give tokens to user 1 and user 2
        deal(address(wstETH), alice, wstInvestAmount);
        deal(address(wstETH), bob, wstInvestAmount * 2);
        deal(address(wstETH), team, wstInvestAmount * 10);
        deal(address(wstETH), address(101), 1e17);

        uint256 startingAliceBalance = wstETH.balanceOf(alice);
        uint256 startingBobBalance = wstETH.balanceOf(bob);

        // initialize
        levStrat.initialize(investN, dao, controller, powerPool);

        // Team sets rates
        vm.startPrank(address(101));
        wstETH.approve(address(levStrat), 1e17);
        levStrat.deposit(1e17, address(101));
        vm.stopPrank();

        // team deposit
        vm.startPrank(team);
        wstETH.approve(address(levStrat), wstInvestAmount * 10);
        levStrat.deposit(wstInvestAmount * 10, team);
        vm.stopPrank();

        // invest

        // user 1 deposit
        vm.startPrank(alice);
        wstETH.approve(address(levStrat), wstInvestAmount);
        levStrat.deposit(wstInvestAmount, alice);
        vm.stopPrank();

        // user 2 deposit
        vm.startPrank(bob);
        wstETH.approve(address(levStrat), wstInvestAmount * 2);
        levStrat.deposit(wstInvestAmount * 2, bob);
        vm.stopPrank();
        uint256 contractWeth = wstETH.balanceOf(address(levStrat));
        console2.log("Contract balance: ", contractWeth);

        // invest
        vm.prank(controller);
        levStrat.invest(bptExpected);

        uint256[4] memory userState = crvUSDController.user_state(address(levStrat));
        console2.log("Collateral:", userState[0]);
        console2.log("tracked collateral: ", levStrat.totalWsthethDeposited());

        uint256 beforeRedeemAliceBalance = levStrat.balanceOf(alice);
        uint256 beforeRedeemBobBalance = levStrat.balanceOf(bob);
        uint256 beforeRedeemTeam = levStrat.balanceOf(team);
        contractWeth = wstETH.balanceOf(address(levStrat));
        console2.log("Contract balance: ", contractWeth);
        console2.log(beforeRedeemAliceBalance);
        console2.log(beforeRedeemBobBalance);
        console2.log(beforeRedeemTeam);

        // user 1 withdraw
        uint256 amountOfVaultSharesToWithdraw = levStrat.balanceOf(alice);
        vm.startPrank(alice);
        levStrat.approve(address(levStrat), amountOfVaultSharesToWithdraw);
        levStrat.redeemWstEth(amountOfVaultSharesToWithdraw, alice, alice, minAmountOut);
        vm.stopPrank();

        // user 2 withdraw
        amountOfVaultSharesToWithdraw = levStrat.balanceOf(bob);
        vm.startPrank(bob);
        levStrat.approve(address(levStrat), amountOfVaultSharesToWithdraw);
        levStrat.redeemWstEth(amountOfVaultSharesToWithdraw, bob, bob, minAmountOut);
        vm.stopPrank();

        amountOfVaultSharesToWithdraw = levStrat.balanceOf(team);
        vm.startPrank(team);
        levStrat.approve(address(levStrat), amountOfVaultSharesToWithdraw);
        levStrat.redeemWstEth(amountOfVaultSharesToWithdraw, team, team, minAmountOut);
        vm.stopPrank();

        contractWeth = wstETH.balanceOf(address(levStrat));
        console2.log("Contract balance: ", contractWeth);

        uint256 afterRedeemAliceBalance = wstETH.balanceOf(alice);
        uint256 afterRedeemBobBalance = wstETH.balanceOf(bob);
        uint256 afterRedeemTeamBalance = wstETH.balanceOf(team);

        userState = crvUSDController.user_state(address(levStrat));
        console2.log("Collateral:", userState[0]);
        console2.log("tracked collateral: ", levStrat.totalWsthethDeposited());
        // ensure user 1 receives the funds, vault shares are burnt and no funds is wasted
        console2.log("Alice wstEth Returned: ", afterRedeemAliceBalance);
        console2.log("Bob wstEth Returned: ", afterRedeemBobBalance);
        console2.log("Team wstEth Returned: ", afterRedeemTeamBalance);
    }

    function test_revert_RedeemOrWithdraw() public {
        // give tokens to user 1 and user 2
        deal(address(wstETH), alice, wstInvestAmount);

        uint256 startingAliceBalance = wstETH.balanceOf(alice);
        uint256 startingBobBalance = wstETH.balanceOf(bob);

        // initialize
        levStrat.initialize(investN, dao, controller, powerPool);

        // // user 1 deposit
        // vm.startPrank(alice);
        // wstETH.approve(address(levStrat), wstInvestAmount);
        // levStrat.deposit(wstInvestAmount, alice);
        // vm.stopPrank();

        // // invest
        // vm.prank(controller);
        // levStrat.invest(bptExpected);

        // // user 2 deposit
        // vm.startPrank(bob);
        // wstETH.approve(address(levStrat), wstInvestAmount * 2);
        // levStrat.deposit(wstInvestAmount * 2, bob);
        // vm.stopPrank();

        // // invest
        // vm.prank(controller);
        // levStrat.invest(bptExpected);

        // uint256 beforeRedeemAliceBalance = wstETH.balanceOf(alice);
        // uint256 beforeRedeemBobBalance = wstETH.balanceOf(bob);

        // user 1 withdraw
        uint256 amountOfVaultSharesToWithdraw = levStrat.balanceOf(alice);
        vm.startPrank(alice);
        levStrat.approve(address(levStrat), amountOfVaultSharesToWithdraw);
        vm.expectRevert(LeverageStrategyStorage.UseOverLoadedRedeemFunction.selector);
        levStrat.redeem(amountOfVaultSharesToWithdraw, alice, alice);
        vm.expectRevert(LeverageStrategyStorage.UseOverLoadedRedeemFunction.selector);
        levStrat.withdraw(amountOfVaultSharesToWithdraw, alice, alice);
        vm.stopPrank();
    }

    function test_UserWithdrawByApprovedUser() public {
        // give tokens to user 1 and user 2
        deal(address(wstETH), alice, wstInvestAmount);
        deal(address(wstETH), bob, wstInvestAmount * 2);
        deal(address(wstETH), team, wstInvestAmount);

        uint256 startingAliceBalance = wstETH.balanceOf(alice);
        uint256 startingBobBalance = wstETH.balanceOf(bob);

        // initialize
        levStrat.initialize(investN, dao, controller, powerPool);

        // set approval for tokens to charlie
        vm.prank(alice);
        levStrat.approve(charlie, type(uint256).max);
        vm.prank(bob);
        levStrat.approve(charlie, type(uint256).max);
        vm.prank(team);
        levStrat.approve(charlie, type(uint256).max);

        // team deposit
        vm.startPrank(team);
        wstETH.approve(address(levStrat), wstInvestAmount);
        levStrat.deposit(wstInvestAmount, team);
        vm.stopPrank();

        // invest
        vm.prank(controller);
        levStrat.invest(bptExpected);

        // user 1 deposit
        vm.startPrank(alice);
        wstETH.approve(address(levStrat), wstInvestAmount);
        levStrat.deposit(wstInvestAmount, alice);
        vm.stopPrank();

        // invest
        vm.prank(controller);
        levStrat.invest(bptExpected);

        // user 2 deposit
        vm.startPrank(bob);
        wstETH.approve(address(levStrat), wstInvestAmount * 2);
        levStrat.deposit(wstInvestAmount * 2, bob);
        vm.stopPrank();

        // invest
        vm.prank(controller);
        levStrat.invest(bptExpected);

        uint256 beforeRedeemAliceBalance = wstETH.balanceOf(alice);
        uint256 beforeRedeemBobBalance = wstETH.balanceOf(bob);

        // user 1 withdraw
        uint256 amountOfVaultSharesToWithdraw = levStrat.balanceOf(alice);
        vm.prank(alice);
        levStrat.approve(address(levStrat), amountOfVaultSharesToWithdraw);
        vm.prank(charlie);
        levStrat.redeemWstEth(amountOfVaultSharesToWithdraw, alice, alice, minAmountOut);

        // user 2 withdraw
        amountOfVaultSharesToWithdraw = levStrat.balanceOf(bob);
        vm.prank(bob);
        levStrat.approve(address(levStrat), amountOfVaultSharesToWithdraw);
        vm.prank(charlie);
        levStrat.redeemWstEth(amountOfVaultSharesToWithdraw, bob, bob, minAmountOut);

        uint256 afterRedeemAliceBalance = wstETH.balanceOf(alice);
        uint256 afterRedeemBobBalance = wstETH.balanceOf(bob);

        // ensure user 1 receives the funds, vault shares are burnt and no funds is wasted
        assertLt(beforeRedeemAliceBalance, afterRedeemAliceBalance);
        assertLt(startingAliceBalance, afterRedeemAliceBalance);
        assertLt(beforeRedeemBobBalance, afterRedeemBobBalance);
        assertGt(startingBobBalance, afterRedeemBobBalance);
    }

    function test_cancelDepositAndInvestFromKeeper() public {
        // give tokens to user 1 and user 2
        deal(address(wstETH), alice, wstInvestAmount * 2);
        deal(address(wstETH), bob, wstInvestAmount * 2);
        deal(address(wstETH), team, wstInvestAmount);

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
        vm.prank(controller);
        levStrat.invest(bptExpected);

        // user 1 deposit
        vm.startPrank(alice);
        wstETH.approve(address(levStrat), wstInvestAmount);
        levStrat.deposit(wstInvestAmount, alice);
        vm.stopPrank();

        // user 2 deposit
        vm.startPrank(bob);
        wstETH.approve(address(levStrat), wstInvestAmount * 2);
        levStrat.deposit(wstInvestAmount * 2, bob);
        vm.stopPrank();

        // user 1 makes another deposit
        vm.startPrank(alice);
        wstETH.approve(address(levStrat), wstInvestAmount);
        levStrat.deposit(wstInvestAmount, alice);

        // user 1 cancels the deposit
        // the key of the deposit can be fetched used the event, as this is a test, we know the key
        assertEq(wstETH.balanceOf(alice), 0);
        levStrat.cancelDeposit(4);
        assertEq(wstETH.balanceOf(alice), wstInvestAmount);
        // cannot cancel deposit again
        vm.expectRevert(LeverageStrategyStorage.DepositCancellationNotAllowed.selector);
        levStrat.cancelDeposit(4);
        assertEq(wstETH.balanceOf(alice), wstInvestAmount);

        vm.stopPrank();

        // invest
        vm.prank(controller);
        levStrat.invest(bptExpected);
    }

    function test_revert_cancelDepositWhenAlreadyDeposited() public {
        // give tokens to user 1 and user 2
        deal(address(wstETH), alice, wstInvestAmount * 2);

        uint256 startingAliceBalance = wstETH.balanceOf(alice);
        uint256 startingBobBalance = wstETH.balanceOf(bob);

        // initialize
        levStrat.initialize(investN, dao, controller, powerPool);

        // user 1 deposit
        vm.startPrank(alice);
        wstETH.approve(address(levStrat), wstInvestAmount);
        levStrat.deposit(wstInvestAmount, alice);
        vm.stopPrank();

        // user 1 makes another deposit
        vm.startPrank(alice);
        wstETH.approve(address(levStrat), wstInvestAmount);
        levStrat.deposit(wstInvestAmount, alice);
        vm.stopPrank();

        // invest
        vm.prank(controller);
        levStrat.invest(bptExpected);

        // cancel deposit after being invested
        // user 1 cancels the deposit
        // the key of the deposit can be fetched used the event, as this is a test, we know the key
        vm.startPrank(alice);
        vm.expectRevert(LeverageStrategyStorage.DepositCancellationNotAllowed.selector);
        levStrat.cancelDeposit(4);
        assertEq(wstETH.balanceOf(alice), 0);
        vm.stopPrank();
    }

    function test_revert_CancelDepositWithUnknownExecutor() public {
        // give tokens to user 1 and user 2
        deal(address(wstETH), alice, wstInvestAmount * 2);

        uint256 startingAliceBalance = wstETH.balanceOf(alice);
        uint256 startingBobBalance = wstETH.balanceOf(bob);

        // initialize
        levStrat.initialize(investN, dao, controller, powerPool);

        // user 1 deposit
        vm.startPrank(alice);
        wstETH.approve(address(levStrat), wstInvestAmount);
        levStrat.deposit(wstInvestAmount, alice);
        vm.stopPrank();

        // user 1 makes another deposit
        vm.startPrank(alice);
        wstETH.approve(address(levStrat), wstInvestAmount);
        levStrat.deposit(wstInvestAmount, alice);
        vm.stopPrank();

        // user 1 cancels the deposit
        // the key of the deposit can be fetched used the event, as this is a test, we know the key
        assertEq(wstETH.balanceOf(alice), 0);
        vm.expectRevert(LeverageStrategyStorage.UnknownExecuter.selector);
        levStrat.cancelDeposit(2);
        assertEq(wstETH.balanceOf(alice), 0);
    }
}
