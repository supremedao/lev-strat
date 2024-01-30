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
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./Tokens.sol";

/// @title Balancer Utility Functions
/// @author SupremeDAO
/// @notice Provides utility functions for interacting with Balancer V2 contracts.
/// @dev This abstract contract includes functions for joining and exiting pools, swapping rewards, and utility functions related to Balancer.
abstract contract BalancerUtils is Tokens {
    /// @notice Address of the Balancer V2 Vault.
    IBalancerVault public constant BAL_VAULT = IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

    /// @notice Pool ID for the Balancer pool containing BAL and WETH.
    bytes32 public constant POOL_BAL_WETH_ID = 0x5c6ee304399dbdb9c8ef030ab642b10820db8f56000200000000000000000014;

    /// @notice Pool ID for the Balancer pool containing AURA and WETH.
    bytes32 public constant POOL_AURA_WETH_ID = 0xcfca23ca9ca720b6e98e3eb9b6aa0ffc4a5c08b9000200000000000000000274;

    /// @notice Pool ID for the Balancer pool containing wstETH and WETH.
    bytes32 public constant POOL_WSTETH_WETH_ID = 0x93d199263632a4ef4bb438f1feb99e57b4b5f0bd0000000000000000000005c2;

    /// @notice A fixed limit used for certain Balancer operations.
    uint256 public constant FIXED_LIMIT = 1;

    /// @notice An empty bytes value used for Balancer user data where no data is needed.
    bytes public constant EMPTY_USER_DATA = "";

    /// @notice The pool ID of the D2D/USDC Balancer pool.
    /// @dev Set upon contract deployment and immutable afterwards.
    bytes32 public immutable POOL_ID;

    /// @dev Sets the pool ID upon contract deployment.
    /// @param _poolId The immutable pool ID for the D2D/USDC Balancer pool.
    constructor(bytes32 _poolId) {
        POOL_ID = _poolId;
    }

    /// @notice Joins a Balancer pool using specified amounts of USDC and D2D.
    /// @dev Approves and then joins the pool with specified amounts, expecting a minimum BPT out.
    /// @param usdcAmount The amount of USDC to deposit into the pool.
    /// @param d2dAmount The amount of D2D to deposit into the pool.
    /// @param minBptAmountOut The minimum amount of Balancer Pool Tokens (BPT) expected out of the transaction.
    function _joinPool(uint256 usdcAmount, uint256 d2dAmount, uint256 minBptAmountOut) internal {
        // Get the tokens involved in the pool
        (IERC20[] memory tokens,,) = BAL_VAULT.getPoolTokens(POOL_ID);
        uint256[] memory maxAmountsIn = new uint256[](tokens.length);

        // Set the amounts for D2D and USDC according to their positions in the pool
        maxAmountsIn[0] = d2dAmount; // D2D token amount
        maxAmountsIn[1] = usdcAmount; // USDC token amount

        // Approve the Balancer Vault to withdraw the respective tokens
        require(IERC20(tokens[0]).approve(address(BAL_VAULT), d2dAmount), "D2D Approval failed");
        require(IERC20(tokens[1]).approve(address(BAL_VAULT), usdcAmount), "USDC Approval failed");

        // Encode user data for pool joining
        uint256 joinKind = uint256(IBalancerVault.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT);
        bytes memory userData = abi.encode(joinKind, maxAmountsIn, minBptAmountOut);

        // Create the request to join the pool
        IBalancerVault.JoinPoolRequest memory request = IBalancerVault.JoinPoolRequest({
            assets: _convertERC20sToAssets(tokens),
            maxAmountsIn: maxAmountsIn,
            userData: userData,
            fromInternalBalance: false
        });

        // Execute the pool joining
        BAL_VAULT.joinPool(POOL_ID, address(this), address(this), request);
    }

    /// @notice Exits a Balancer pool, specifying a single token to receive out.
    /// @dev Withdraws from the pool, receiving a specific token, with a minimum amount expected.
    /// @param bptAmountIn The amount of BPT to provide for the exit.
        /// @param exitTokenIndex The index of the token to receive out of the pool.
    /// @param minAmountOut The minimum amount of the token to receive from the exit.
    function _exitPool(uint256 bptAmountIn, uint256 exitTokenIndex, uint256 minAmountOut) internal {
        // Get the tokens involved in the pool
        (IERC20[] memory tokens,,) = BAL_VAULT.getPoolTokens(POOL_ID);
        uint256[] memory minAmountsOut = new uint256[](tokens.length);
        minAmountsOut[exitTokenIndex] = minAmountOut;

        // Define the exit kind and encode user data
        uint256 exitKind = uint256(IBalancerVault.ExitKind.EXACT_BPT_IN_FOR_ONE_TOKEN_OUT);
        bytes memory userData = abi.encode(exitKind, bptAmountIn, exitTokenIndex);

        // Create the request to exit the pool
        IBalancerVault.ExitPoolRequest memory request = IBalancerVault.ExitPoolRequest({
            assets: _convertERC20sToAssets(tokens),
            minAmountsOut: minAmountsOut,
            userData: userData,
            toInternalBalance: false
        });

        // Execute the pool exit
        BAL_VAULT.exitPool(POOL_ID, address(this), payable(address(this)), request);
    }

    /// @notice Swaps BAL rewards for WETH using Balancer.
    /// @dev Performs a single asset swap from BAL to WETH in the Balancer pool.
    /// @param balAmount The amount of BAL to swap.
    /// @param minWethAmount The minimum amount of WETH expected from the swap.
    /// @param deadline The deadline by which the swap must be completed.
    function _swapRewardBal(uint256 balAmount, uint256 minWethAmount, uint256 deadline) internal {
        // Approve the Balancer Vault to swap BAL
        IERC20(BAL).approve(address(BAL_VAULT), balAmount);

        // Set up the single swap details
        IBalancerVault.SingleSwap memory singleSwap = IBalancerVault.SingleSwap({
            poolId: POOL_BAL_WETH_ID,
            kind: IBalancerVault.SwapKind.GIVEN_IN,
            assetIn: IAsset(BAL),
            assetOut: IAsset(WETH),
            amount: balAmount,
            userData: EMPTY_USER_DATA
        });

        // Define the fund management for the swap
        IBalancerVault.FundManagement memory funds = IBalancerVault.FundManagement({
            sender: address(this),
            fromInternalBalance: false,
            recipient: payable(address(this)),
            toInternalBalance: false
        });

        // Execute the swap on Balancer
        BAL_VAULT.swap(singleSwap, funds, minWethAmount, deadline);
    }

    /// @notice Swaps AURA rewards for WETH using Balancer.
    /// @dev Performs a single asset swap from AURA to WETH in the Balancer pool.
    /// @param auraAmount The amount of AURA to swap.
    /// @param minWethAmount The minimum amount of WETH expected from the swap.
    /// @param deadline The deadline by which the swap must be completed.
    function _swapRewardAura(uint256 auraAmount, uint256 minWethAmount, uint256 deadline) internal {
        // Approve the Balancer Vault to swap AURA
        IERC20(AURA).approve(address(BAL_VAULT), auraAmount);

        // Set up the single swap details
        IBalancerVault.SingleSwap memory singleSwap = IBalancerVault.SingleSwap({
            poolId: POOL_AURA_WETH_ID,
            kind: IBalancerVault.SwapKind.GIVEN_IN,
            assetIn: IAsset(AURA),
            assetOut: IAsset(WETH),
            amount: auraAmount,
            userData: EMPTY_USER_DATA
        });

        // Define the fund management for the swap
        IBalancerVault.FundManagement memory funds = IBalancerVault.FundManagement({
            sender: address(this),
            fromInternalBalance: false,
            recipient: payable(address(this)),
            toInternalBalance: false
        });

        // Execute the swap on Balancer
        BAL_VAULT.swap(singleSwap, funds, minWethAmount, deadline);
    }

    /// @notice Swaps WETH for wstETH using Balancer.
    /// @dev Performs a single asset swap from WETH to wstETH in the Balancer pool.
    /// @param minWethAmount The minimum amount of WETH to swap.
    /// @param deadline The deadline by which the swap must be completed.
    function _swapRewardToWstEth(uint256 minWethAmount, uint256 deadline) internal {
        // Approve the Balancer Vault to swap WETH
        IERC20(WETH).approve(address(BAL_VAULT), minWethAmount);

        // Set up the single swap details
        IBalancerVault.SingleSwap memory singleSwap = IBalancerVault.SingleSwap({
            poolId: POOL_WSTETH_WETH_ID,
            kind: IBalancerVault.SwapKind.GIVEN_IN,
            assetIn: IAsset(WETH),
            assetOut: IAsset(address(wstETH)),
            amount: minWethAmount,
            userData: EMPTY_USER_DATA
        });

        // Define the fund management for the swap
        IBalancerVault.FundManagement memory funds = IBalancerVault.FundManagement({
            sender: address(this),
            fromInternalBalance: false,
            recipient: payable(address(this)),
            toInternalBalance: false
        });

        // Execute the swap on Balancer
        BAL_VAULT.swap(singleSwap, funds, minWethAmount, deadline);
    }

    /// @dev Converts an array of IERC20 tokens to an array of IAsset.
    /// @param tokens The array of IERC20 tokens to convert.
    /// @return assets The converted array of IAsset.
    function _convertERC20sToAssets(IERC20[] memory tokens) internal pure returns (IAsset[] memory assets) {
        // Inline assembly for efficient conversion between IERC20[] and IAsset[]
        // solhint-disable-next-line no-inline-assembly
        assembly {
            assets := tokens
        }
    }
}

