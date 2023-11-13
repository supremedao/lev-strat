pragma solidity ^0.8.0;
import {BaseLeverageStrategyTest} from "./utils/BaseLeverageStrategyTest.sol";
import {console} from "forge-std/console.sol";
 
contract LeverageStrategyTest is BaseLeverageStrategyTest {

    function setUp() public {
        _deployContracts();
    }


    function testInvest() public subtest() {
        

        address testContract = address(0x13425136);

        uint before = crvUSD.balanceOf(alice);
        // Give wsteth tokens to alice's account
        deal(address(wstETH),alice, wstEthToAcc);
        
        levStrat.initializeContracts(address(AuraBooster), address(balancerVault), address(crvUSD), address(crvUSDController), address(crvUSDUSDCPool), address(wstETH), address(usdc), address(d2d));

        // Make alice msg.sender
        vm.startPrank(alice);
        wstETH.approve(address(levStrat), maxApprove);
        levStrat.invest(wstInvestAmount , debtAmount, insvestN);
        vm.stopPrank();
        uint aft = circle_deployer.balanceOf(address(levStrat));
        console.log("bal aft",aft);
        assertGt(aft,0);

    }

    function testInvestIfCDPAlreadyExists() public subtest(){
        
        uint before = crvUSD.balanceOf(address(levStrat));
        console.log("bal b4",before);

        // Give wsteth tokens to alice's account
        deal(address(wstETH),alice, wstEthToAcc);
  

        wstETH.approve(address(levStrat), maxApprove);
     
        levStrat.initializeContracts(address(AuraBooster), address(balancerVault), address(crvUSD), address(crvUSDController), address(crvUSDUSDCPool), address(wstETH), address(usdc), address(d2d));        //levStrat.initializeContracts(_auraBooster, _balancerVault, _crvUSD, _crvUSDController, _crvUSDUSDCPool, _wstETH, _USDC, _D2D);

        // Make alice msg.sender
        vm.startPrank(alice);
        wstETH.approve(address(levStrat), maxApprove);
        levStrat.invest(wstInvestAmount , debtAmount, insvestN);
        levStrat.invest(wstInvestAmount , debtAmount, insvestN);
        vm.stopPrank();

                
        uint aft = circle_deployer.balanceOf(address(levStrat));
        console.log("bal aft",aft);
        assertGt(aft,0);


    }



}