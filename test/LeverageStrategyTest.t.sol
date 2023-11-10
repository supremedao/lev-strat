pragma solidity ^0.8.0;
import {BaseLeverageStrategyTest} from "./utils/BaseLeverageStrategyTest.sol";
import {console} from "forge-std/console.sol";
 
contract LeverageStrategyTest is BaseLeverageStrategyTest {

    function setUp() public {
        _deployContracts();
    }


    function testInvest() public subtest() {
        
        uint aliceAmount = 7 * 1e18;
        uint wstApproveAmount = 2**256 - 1;
        uint wstInvestAmount = 3 * 1e18;
        uint debtAmount = 5000000;
        uint insvestN = 10;

        address testContract = address(0x13425136);

        uint before = crvUSD.balanceOf(alice);
        // Give wsteth tokens to alice's account
        deal(address(wstETH),alice, wstEthToAcc);
        
        levStrat.initializeContracts(address(AuraBooster), address(balancerVault), address(crvUSD), address(crvUSDController), address(crvUSDUSDCPool), address(wstETH), address(usdc), address(d2d));

        // Make alice msg.sender
        vm.startPrank(alice);
        wstETH.approve(address(levStrat), maxApprove);
        levStrat.invest(2 * 1e18 , 1000000, 10);
        vm.stopPrank();
        uint aft = crvUSD.balanceOf(address(levStrat));
        console.log("bal aft",aft);

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
        levStrat.invest(1 * 1e18 , 1000000, 10);
        levStrat.invest(1 * 1e18 , 1000000, 10);
        vm.stopPrank();

                
        uint aft = crvUSD.balanceOf(address(levStrat));
        console.log("bal aft",aft);


    }



}