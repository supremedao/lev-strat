pragma solidity ^0.8.10;

import "../utils/BaseTest.sol";
import "forge-std/console.sol";
import {StrategyResolver, Tokens} from "../../contracts/HFUnwindResolver.sol";
import "../mocks/LeverageStrategyMock.sol";
import "../mocks/wstETHMock.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract ResolverTest is BaseTest, Tokens {

    LeverageStrategy public leverageStrategy;
    StrategyResolver public resolver;

    MockWSTETH public mockWSTETH;

    bytes32 public mockPid = 0x27c9f71cc31464b906e0006d4fcbc8900f48f15f00020000000000000000010f;

    function setUp() public {
        // Setting up a mock pool
        leverageStrategy = new LeverageStrategy(mockPid);
        // Setup the Resolver
        resolver = new StrategyResolver(address(leverageStrategy));

        mockWSTETH = new MockWSTETH();
        // Because we aren't running in a forked env, but we still need a token at the wstETH address because it's declared constant
        // we deploy the code for an ERC20 at the usual wstETH address (which would be clean in our non-forked env)
        bytes memory tokenCode = vm.getDeployedCode("wstETHMock.sol:MockWSTETH");
        vm.etch(address(wstETH), tokenCode);
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

    // Case: check the Strategy balance and return the call data required to queue an invest call
    function test_success_checkBalanceAndReturnCalldata(uint256 wstEthAmountBalance) public {
        vm.assume(wstEthAmountBalance > 0);
        // Give the contract a wstETH balance
        deal(address(wstETH), address(leverageStrategy), wstEthAmountBalance);
        (bool flag, bytes memory returnedData) = resolver.checkBalanceAndReturnCalldata();

        if (wstEthAmountBalance > resolver.investThreshold()) {
            // Check return flag
            assert(flag);
            // Check the selector
            assertEq(bytes4(returnedData), LeverageStrategy.investFromKeeper.selector);
        } else {
            assert(!flag);
            assertEq(returnedData, "");
        }
    }

    // Case: success, no unwind queued, calldata == queue new unwind 
    function test_success_checkAndReturnCalldata_NoUnwindQueued(uint256 balance) public {
        vm.assume(balance > 1 ether);

        // Now we call the Resolver and expect the resolver to return the UnwindPositionFromKeeper call
        (bool flag, bytes memory cdata) = resolver.checkAndReturnCalldata();
        assertEq(bytes4(cdata), LeverageStrategy.unwindPositionFromKeeper.selector);

    }

    // Case: success, unwind queued, calldata == executeUnwind
    function test_success_checkAndReturnCalldata_UnwindQueued(uint256 balance) public {
        // We queue an unwind
        uint256 time = block.timestamp;
        leverageStrategy.unwindPositionFromKeeper();

        vm.warp(time + 12);
        (bool flag, bytes memory cdata) = resolver.checkAndReturnCalldata();
        assertEq(bytes4(cdata), LeverageStrategy.executeUnwindFromKeeper.selector);
    }

    // Case: success, no unwind needed, calldata == bytes("")
    function test_success_checkAndReturnCalldata_No_Unwind_Needed(int256 amount) public {
        vm.assume(amount > 0);
        leverageStrategy.setStrategyHealth(amount);
        (bool flag, bytes memory cdata) = resolver.checkAndReturnCalldata();
        assertFalse(flag);
        assertEq(cdata, bytes(""));
    }

}