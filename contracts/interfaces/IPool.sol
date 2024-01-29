// Interface for Pool Queries
pragma solidity ^0.8.0;

interface IPool {
    function getSwapFeePercentage() external returns (uint256);

    /**
     * @dev Returns the amount of BPT that would be burned from `sender` if the `onExitPool` hook were called by the
     * Vault with the same arguments, along with the number of tokens `recipient` would receive.
     *
     * This function is not meant to be called directly, but rather from a helper contract that fetches current Vault
     * data, such as the protocol swap fee percentage and Pool balances.
     *
     * Like `IVault.queryBatchSwap`, this function is not view due to internal implementation details: the caller must
     * explicitly use eth_call instead of eth_sendTransaction.
     */
    function queryExit(
        bytes32 poolId,
        address sender,
        address recipient,
        uint256[] memory balances,
        uint256 lastChangeBlock,
        uint256 protocolSwapFeePercentage,
        bytes memory userData
    ) external returns (uint256 bptIn, uint256[] memory amountsOut);
}
