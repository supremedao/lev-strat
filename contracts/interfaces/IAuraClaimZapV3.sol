// transaction example: https://etherscan.io/tx/0xd55ae74918f870182291e9d64c5f20dc51f64c52805f3c4a0da1098455cf42a6

pragma solidity ^0.8.0;

contract IAuraClaimZapV3 {

    function claimRewards(
        address[] calldata rewardContracts,
        address[] calldata extraRewardContracts,
        address[] calldata tokenRewardContracts,
        address[] calldata tokenRewardTokens,
        ClaimRewardsAmounts calldata amounts,
        Options calldata options
    ) external;

}