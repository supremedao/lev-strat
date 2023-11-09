pragma solidity ^0.8.0;
import {BaseLeverageStrategyTest} from "./utils/BaseLeverageStrategyTest.sol";
import {console} from "forge-std/console.sol";
 
contract LeverageStrategyTest is BaseLeverageStrategyTest {

    function setUp() public {
        _deployContracts();
    }


    function testInvest() public {
        
        uint aliceAmount = 7 * 1e18;
        uint wstApproveAmount = 2**256 - 1;
        uint wstInvestAmount = 3 * 1e18;
        uint debtAmount = 5000000;
        uint insvestN = 10;

        address testContract = address(0x13425136);

        uint before = crvUSD.balanceOf(alice);

        deal(address(wstETH),alice, aliceAmount);
        deal(address(wstETH),address(this), aliceAmount);

        

        wstETH.approve(address(levStrat), wstApproveAmount);

        // @dev levStrat.initializeContracts(_auraBooster, _balancerVault, _crvUSD, _crvUSDController, _crvUSDUSDCPool, _wstETH, _USDC, _D2D)
        levStrat.initializeContracts(testContract, testContract, address(crvUSD), address(crvUSDController), testContract, address(wstETH), address(usdc), testContract);

        vm.prank(alice);
        wstETH.approve(address(levStrat), wstApproveAmount);
        levStrat.invest(wstInvestAmount, debtAmount, insvestN);
        vm.stopPrank();

        uint aft = crvUSD.balanceOf(address(levStrat));
        console.log("bal aft",aft);

    }



}