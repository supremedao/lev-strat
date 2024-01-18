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
        levStrat.unwindPosition(amounts);

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

        console2.log("debt b4", debt_before);

        vm.prank(powerPool);
        levStrat.unwindPositionFromKeeper();

        uint256 debt_after = crvUSDController.debt(address(levStrat));

        console2.log("debt b4 2nd check", debt_before);

        console2.log("debt aft", debt_after);

        assertGt(debt_before, debt_after);
    }
}
