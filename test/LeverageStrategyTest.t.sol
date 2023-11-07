pragma solidity ^0.8.0;
import {BaseLeverageStrategyTest} from "./utils/BaseLeverageStrategyTest.sol";
import {console} from "forge-std/console.sol";
 
contract LeverageStrategyTest is BaseLeverageStrategyTest {

    function setUp() public {
        _deployContracts();
    }


    function testInvest() public {
        
        uint before = crvUSD.balanceOf(alice);

        deal(address(wstETH),alice, 7 * 1e18);
        deal(address(wstETH),address(this), 7 * 1e18);

        

        wstETH.approve(address(levStrat), 2**256 - 1);

        

        //wstETH.approve(address(levStrat), 25 * 1e18);
        levStrat.initializeContracts(address(0x13425136), address(0x13425136), address(crvUSD), address(crvUSDController), address(0x13425136), address(wstETH), address(usdc), address(0x13425136));

        //levStrat.initializeContracts(_auraBooster, _balancerVault, _crvUSD, _crvUSDController, _crvUSDUSDCPool, _wstETH, _USDC, _D2D);

        vm.prank(alice);
        wstETH.approve(address(levStrat), 2**256 - 1);
        levStrat.invest(3 * 1e18 , 5000000, 10);
        vm.stopPrank();

        uint aft = crvUSD.balanceOf(address(levStrat));
        console.log("bal aft",aft);

    }



}