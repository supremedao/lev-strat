pragma solidity ^0.8.10;

import "../utils/BaseTest.sol";
import {StrategyResolver} from "../../contracts/HFUnwindResolver.sol";
import "../mocks/LeverageStrategyMock.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract ResolverTest is BaseTest {

    LeverageStrategy public leverageStrategy;
    StrategyResolver public resolver;

    bytes32 public mockPid = 0x27c9f71cc31464b906e0006d4fcbc8900f48f15f00020000000000000000010f;

    function setUp() public {
        // Setting up a mock pool
        leverageStrategy = new LeverageStrategy(mockPid);
        // Setup the Resolver
        resolver = new StrategyResolver(address(leverageStrategy));
    }

    // Case: `checkCondition` returns the appropriate boolean
    function test_CheckCondition(int256 currentHealth) external {
        // Change the Strategy Health
        leverageStrategy.setStrategyHealth(currentHealth);
        // We assert that the `checkCondition` returns the appropriate value
        if (currentHealth <= 0) {
            assertTrue(resolver.checkCondition());
        } else {
            assertFalse(resolver.checkCondition());
        }
    }

    // Case: set new InvestThreshold, Owner
    function test_success_setInvestThreshold(uint256 amount) public {
        vm.assume(amount != 0);

        resolver.setInvestThreshold(amount);
    }

    // Case: set new InvestThreshold, not Owner
    function test_fail_setInvestThreshold(uint256 amount, address caller) public {
        vm.assume(amount != 0);
        vm.assume(caller != address(this) && caller != address(0));

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, caller));
        vm.prank(caller);
        resolver.setInvestThreshold(amount);
    }

    // Case: set new unwindThreshold, Owner
    function test_success_setUnwindThreshold(int256 threshold) public {
        resolver.setUnwindthreshold(threshold);
    }

    // Case: set new unwindThreshold, not Owner
    function test_fail_setUnwindThreshold(int256 threshold, address caller) public {
        vm.assume(caller != address(this) && caller != address(0));

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, caller));
        vm.prank(caller);
        resolver.setUnwindthreshold(threshold);
    }

}