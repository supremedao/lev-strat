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
            address(d2d)
        );

        // Make alice msg.sender
        vm.startPrank(alice);
        wstETH.approve(address(levStrat), maxApprove);

        levStrat.invest(wstInvestAmount, debtAmount, insvestN, bptExpected);
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
            address(d2d)
        ); //levStrat.initializeContracts(_auraBooster, _balancerVault, _crvUSD, _crvUSDController, _crvUSDUSDCPool, _wstETH, _USDC, _D2D);

        // Make alice msg.sender
        vm.startPrank(alice);
        wstETH.approve(address(levStrat), maxApprove);
        levStrat.invest(wstInvestAmount, debtAmount, insvestN, bptExpected);
        levStrat.invest(wstInvestAmount, debtAmount, insvestN, bptExpected);
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
            address(d2d)
        );

        // Make alice msg.sender
        vm.startPrank(alice);
        wstETH.approve(address(levStrat), maxApprove);

        levStrat.invest(wstInvestAmount, debtAmount, insvestN, bptExpected);
        vm.stopPrank();
        uint256 aft = AuraLPVault.balanceOf(address(levStrat));
        console.log("bal aft", aft);
        assertGt(aft, 0);

        levStrat.unwindPosition(amounts);
        uint256 aftBPT = d2dusdcBPT.balanceOf(address(levStrat));
        assertGt(aftBPT, 0);
    }
}
