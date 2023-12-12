pragma solidity ^0.8.0;

import {BaseLeverageStrategyTest} from "./utils/BaseLeverageStrategyTest.sol";
import {console2} from "forge-std/console2.sol";

contract LeverageStrategyTest is BaseLeverageStrategyTest {
    function setUp() public {
        _deployContracts();
    }

    function testInvest() public subtest {
        // Wsteth gets deposited into vault
        deal(address(wstETH), vault4626, wstEthToAcc);

        levStrat.initializeContracts(
            address(AuraBooster),
            address(balancerVault),
            address(crvUSD),
            address(crvUSDController),
            address(crvUSDUSDCPool),
            address(wstETH),
            address(usdc),
            address(d2d),
            investN
        );

        // Make vault msg.sender
        vm.prank(vault4626);
        wstETH.transfer(address(levStrat), wstInvestAmount);

        vm.prank(controller);
        levStrat.invest(wstInvestAmount, debtAmount, bptExpected);

        uint256 aft = AuraLPVault.balanceOf(address(levStrat));
        console2.log("bal aft", aft);
        assertGt(aft, 0);
    }

    function testInvestIfCDPAlreadyExists() public subtest {
        uint256 before = AuraLPVault.balanceOf(address(levStrat));
        console2.log("bal b4", before);

        // Give wsteth tokens to alice's account
        deal(address(wstETH), vault4626, wstEthToAcc);

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
            investN
        ); 

        // Make vault msg.sender
        vm.prank(vault4626);
        wstETH.transfer(address(levStrat), wstInvestAmount);

        vm.prank(controller);
        levStrat.invest(wstInvestAmount, debtAmount, bptExpected);

        vm.prank(vault4626);
        wstETH.transfer(address(levStrat), wstInvestAmount);

        vm.prank(controller);
        levStrat.invest(wstInvestAmount, debtAmount, bptExpected);

        uint256 aft = AuraLPVault.balanceOf(address(levStrat));
        console2.log("bal aft", aft);
        assertGt(aft, 0);
    }

    function testUnwind() public subtest {
        // Give wsteth tokens to alice's account
        deal(address(wstETH), vault4626, wstEthToAcc);

        levStrat.initializeContracts(
            address(AuraBooster),
            address(balancerVault),
            address(crvUSD),
            address(crvUSDController),
            address(crvUSDUSDCPool),
            address(wstETH),
            address(usdc),
            address(d2d),
            investN
        );

        // Make vault msg.sender
        vm.prank(vault4626);
        wstETH.transfer(address(levStrat), wstInvestAmount);

        vm.prank(controller);
        levStrat.invest(wstInvestAmount, debtAmount, bptExpected);

        uint256 debt_before = crvUSDController.debt(address(levStrat));
        console2.log("debt b4", debt_before);

        _pushDebtToRepay(1000000);

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

        levStrat.initializeContracts(
            address(AuraBooster),
            address(balancerVault),
            address(crvUSD),
            address(crvUSDController),
            address(crvUSDUSDCPool),
            address(wstETH),
            address(usdc),
            address(d2d),
            investN
        );

        // Make vault msg.sender
        vm.prank(vault4626);
        wstETH.transfer(address(levStrat), wstInvestAmount);

        vm.prank(controller);
        levStrat.invest(wstInvestAmount, debtAmount, bptExpected);

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
