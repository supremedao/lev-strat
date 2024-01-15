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

import "../interfaces/IBalancerVault.sol";
import "../interfaces/IERC20.sol";
import "./Tokens.sol";

abstract contract BalancerUtils is Tokens {
    // address of balancer vault
    // fix: balancer vault is fixed across chains, we can set it as immutable
    IBalancerVault public constant BAL_VAULT = IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);bytes32 public constant POOL_BAL_WETH_ID = 0x5c6ee304399dbdb9c8ef030ab642b10820db8f56000200000000000000000014;
    bytes32 public constant POOL_AURA_WETH_ID = 0xcfca23ca9ca720b6e98e3eb9b6aa0ffc4a5c08b9000200000000000000000274;
    bytes32 public constant POOL_WSTETH_WETH_ID = 0x93d199263632a4ef4bb438f1feb99e57b4b5f0bd0000000000000000000005c2;
    uint256 public constant FIXED_LIMIT = 1;
    bytes public constant EMPTY_USER_DATA = "";

    // pool of D2D/USDC
    bytes32 public immutable POOL_ID;

    constructor(bytes32 _poolId) {
        POOL_ID = _poolId;
    }

    /// @notice Join balancer pool
    /// @dev Single side join with usdc
    /// @param usdcAmount the amount of usdc to deposit
    function _joinPool(uint256 usdcAmount, uint256 d2dAmount, uint256 minBptAmountOut) internal {
        (IERC20[] memory tokens,,) = BAL_VAULT.getPoolTokens(POOL_ID);
        uint256[] memory maxAmountsIn = new uint256[](tokens.length);

        // Set the amounts for D2D and USDC according to their positions in the pool
        maxAmountsIn[0] = d2dAmount; // D2D token amount
        maxAmountsIn[1] = usdcAmount; // USDC token amount

        // Approve the Balancer Vault to withdraw the respective tokens
        require(IERC20(tokens[0]).approve(address(BAL_VAULT), d2dAmount), "D2D Approval failed");
        require(IERC20(tokens[1]).approve(address(BAL_VAULT), usdcAmount), "USDC Approval failed");

        uint256 joinKind = uint256(IBalancerVault.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT);
        bytes memory userData = abi.encode(joinKind, maxAmountsIn, minBptAmountOut);

        IBalancerVault.JoinPoolRequest memory request = IBalancerVault.JoinPoolRequest({
            assets: _convertERC20sToAssets(tokens),
            maxAmountsIn: maxAmountsIn,
            userData: userData,
            fromInternalBalance: false
        });

        BAL_VAULT.joinPool(POOL_ID, address(this), address(this), request);
    }

    function _exitPool(uint256 bptAmountIn, uint256 exitTokenIndex, uint256 minAmountOut) internal {
        (IERC20[] memory tokens,,) = BAL_VAULT.getPoolTokens(POOL_ID);
        uint256[] memory minAmountsOut = new uint256[](tokens.length);
        minAmountsOut[exitTokenIndex] = minAmountOut;

        // Define the exit kind
        uint256 exitKind = uint256(IBalancerVault.ExitKind.EXACT_BPT_IN_FOR_ONE_TOKEN_OUT);
        bytes memory userData = abi.encode(exitKind, bptAmountIn, exitTokenIndex);

        IBalancerVault.ExitPoolRequest memory request = IBalancerVault.ExitPoolRequest({
            assets: _convertERC20sToAssets(tokens),
            minAmountsOut: minAmountsOut,
            userData: userData,
            toInternalBalance: false
        });

        BAL_VAULT.exitPool(POOL_ID, address(this), payable(address(this)), request);
    }


    function _swapRewardBal(uint256 balAmount, uint256 minWethAmount, uint256 deadline) internal {
        IERC20(BAL).approve(address(BAL_VAULT), balAmount);

        IBalancerVault.SingleSwap memory singleSwap = IBalancerVault.SingleSwap({
            poolId: POOL_BAL_WETH_ID,
            kind: IBalancerVault.SwapKind.GIVEN_IN,
            assetIn: IAsset(BAL),
            assetOut: IAsset(WETH),
            amount: balAmount,
            userData: EMPTY_USER_DATA
        });

        IBalancerVault.FundManagement memory funds = IBalancerVault.FundManagement({
            sender: address(this),
            fromInternalBalance: false,
            recipient: payable(address(this)),
            toInternalBalance: false
        });

        BAL_VAULT.swap(singleSwap, funds, FIXED_LIMIT, deadline);
    }

    function _swapRewardAura(uint256 auraAmount, uint256 minWethAmount, uint256 deadline) internal {
        
        IERC20(AURA).approve(address(BAL_VAULT), auraAmount);

        IBalancerVault.SingleSwap memory singleSwap = IBalancerVault.SingleSwap({
            poolId: POOL_AURA_WETH_ID,
            kind: IBalancerVault.SwapKind.GIVEN_IN,
            assetIn: IAsset(AURA),
            assetOut: IAsset(WETH),
            amount: auraAmount,
            userData: EMPTY_USER_DATA
        });

        IBalancerVault.FundManagement memory funds = IBalancerVault.FundManagement({
            sender: address(this),
            fromInternalBalance: false,
            recipient: payable(address(this)),
            toInternalBalance: false
        });

        BAL_VAULT.swap(singleSwap, funds, FIXED_LIMIT, deadline);
    }

    function _swapRewardToWstEth(uint256 minWethAmount, uint256 deadline) internal {
        
        IERC20(WETH).approve(address(BAL_VAULT), minWethAmount);

        IBalancerVault.SingleSwap memory singleSwap = IBalancerVault.SingleSwap({
            poolId: POOL_WSTETH_WETH_ID,
            kind: IBalancerVault.SwapKind.GIVEN_IN,
            assetIn: IAsset(WETH),
            assetOut: IAsset(address(wstETH)),
            amount: minWethAmount,
            userData: EMPTY_USER_DATA
        });

        IBalancerVault.FundManagement memory funds = IBalancerVault.FundManagement({
            sender: address(this),
            fromInternalBalance: false,
            recipient: payable(address(this)),
            toInternalBalance: false
        });

        BAL_VAULT.swap(singleSwap, funds, FIXED_LIMIT, deadline);
    }

    /// @dev This helper function is a fast and cheap way to convert between IERC20[] and IAsset[] types
    function _convertERC20sToAssets(IERC20[] memory tokens) internal pure returns (IAsset[] memory assets) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            assets := tokens
        }
    }
}