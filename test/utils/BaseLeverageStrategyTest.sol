pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {LeverageStrategy} from "../../contracts/LeverageStrategy.sol";
import {IERC20} from "../../contracts/interfaces/IERC20.sol";
import {IcrvUSDController} from "../../contracts/interfaces/IcrvUSDController.sol";
import {IcrvUSDUSDCPool} from "../../contracts/interfaces/IcrvUSDUSDCPool.sol";

contract BaseLeverageStrategyTest is Test {

    LeverageStrategy internal levStrat;
    uint256 testNumber;

    uint256 internal ownerPk = 0x123;
    uint256 internal alicePk = 0xa11ce;
    uint256 internal bobPk = 0xb0b;
    uint256 internal daoPk = 0xDa0;
    address internal owner = vm.addr(ownerPk);
    address internal alice = vm.addr(alicePk);
    address internal bob = vm.addr(bobPk);
    address internal dao = vm.addr(daoPk);


    IERC20 public usdc;
    IERC20 public wstETH;
    IERC20 public crvUSD;
    IERC20 public circle_deployer;
    IcrvUSDController public crvUSDController;
    IcrvUSDUSDCPool public crvUSDUSDCPool;

    function _deployContracts() internal {

        levStrat = new LeverageStrategy(address(dao));

        wstETH = IERC20(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
        usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);  
        crvUSD = IERC20(0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E);
        crvUSDController = IcrvUSDController(0x100dAa78fC509Db39Ef7D04DE0c1ABD299f4C6CE);
        crvUSDUSDCPool = IcrvUSDUSDCPool(0x4DEcE678ceceb27446b35C672dC7d61F30bAD69E); 
        circle_deployer = IERC20(0xa2327a938Febf5FEC13baCFb16Ae10EcBc4cbDCF);


        vm.label(address(levStrat), "LevStrategy");
        vm.label(alice, "Alice");

    }

}