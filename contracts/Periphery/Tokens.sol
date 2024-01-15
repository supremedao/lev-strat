// SPDX-License-Identifier: GPL-3.0-or-later

/*
________                                          ______________________ 
__  ___/___  ____________________________ ___________  __ \__    |_  __ \
_____ \_  / / /__  __ \_  ___/  _ \_  __ `__ \  _ \_  / / /_  /| |  / / /
____/ // /_/ /__  /_/ /  /   /  __/  / / / / /  __/  /_/ /_  ___ / /_/ / 
/____/ \__,_/ _  .___//_/    \___//_/ /_/ /_/\___//_____/ /_/  |_\____/  
              /_/                                                        
*/

pragma solidity ^0.8.0;

import "../interfaces/IcrvUSD.sol";
import "../interfaces/IERC20.sol";

abstract contract Tokens {
    address public constant BAL = 0xba100000625a3754423978a60c9317c58a424e3D;
    address public constant AURA = 0xC0c293ce456fF0ED870ADd98a0828Dd4d2903DBF;
    address public constant WETH = 0xdFCeA9088c8A88A76FF74892C1457C17dfeef9C1;
    IERC20 public constant wstETH = IERC20(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    IERC20 public constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 public constant D2D = IERC20(0x43D4A3cd90ddD2F8f4f693170C9c8098163502ad);
    IERC20 public constant D2D_USDC_BPT = IERC20(0x27C9f71cC31464B906E0006d4FcBC8900F48f15f);
    IcrvUSD public constant crvUSD = IcrvUSD(0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E);

}