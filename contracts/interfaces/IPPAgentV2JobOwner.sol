// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

interface IPPAgentV2JobOwner {
    struct RegisterJobParams {
        address jobAddress;
        bytes4 jobSelector;
        bool useJobOwnerCredits;
        bool assertResolverSelector;
        uint16 maxBaseFeeGwei;
        uint16 rewardPct;
        uint32 fixedReward;
        uint256 jobMinCvp;
        uint8 calldataSource;
        uint24 intervalSeconds;
    }

    struct Job {
        uint8 config;
        bytes4 selector;
        uint88 credits;
        uint16 maxBaseFeeGwei;
        uint16 rewardPct;
        uint32 fixedReward;
        uint8 calldataSource;
        // For interval jobs
        uint24 intervalSeconds;
        uint32 lastExecutionAt;
    }

    struct Resolver {
        address resolverAddress;
        bytes resolverCalldata;
    }

    function registerJob(
        RegisterJobParams calldata params_,
        Resolver calldata resolver_,
        bytes calldata preDefinedCalldata_
    ) external payable returns (bytes32 jobKey, uint256 jobId);

    function getJobKey(
        address jobAddress_,
        uint256 jobId_
    ) external pure returns (bytes32 jobKey);

    function getJobRaw(bytes32 jobKey_) external view returns (uint256 rawJob);

    function jobNextKeeperId(bytes32 jobKey_) external view returns (uint256);

    function getKeeper(
        uint256 keeperId_
    )
    external
    view
    returns (
        address admin,
        address worker,
        bool isActive,
        uint256 currentStake,
        uint256 slashedStake,
        uint256 compensation,
        uint256 pendingWithdrawalAmount,
        uint256 pendingWithdrawalEndAt
    );

    function getJob(
        bytes32 jobKey_
    )
    external
    view
    returns (
        address owner,
        address pendingTransfer,
        uint256 jobLevelMinKeeperCvp,
        Job memory details,
        bytes memory preDefinedCalldata,
        Resolver memory resolver
    );
}