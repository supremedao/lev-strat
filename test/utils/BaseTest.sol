pragma solidity ^0.8.10;

import "forge-std/Test.sol";

contract BaseTest is Test {
    modifier subtest() {
        uint256 snapshot = vm.snapshot();
        _;
        vm.revertTo(snapshot);
    }

    function expectRevert(string memory error) internal {
        return vm.expectRevert(abi.encodeWithSignature(error));
    }
}
