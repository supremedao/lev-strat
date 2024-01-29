pragma solidity ^0.8.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockWSTETH is ERC20 {
    constructor() ERC20("Mock", "mck") {}
}
