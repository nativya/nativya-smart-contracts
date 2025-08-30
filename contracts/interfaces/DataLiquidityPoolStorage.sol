// SPDX-License-Identifier: MIT
pragma solidity 0.8.12;

import "./IDataLiquidityPool.sol";

/**
 * @title Storage for DataLiquidityPool
 * @notice For future upgrades, do not change DataLiquidityPoolStorageV1. Create a new
 * contract which implements DataLiquidityPoolStorageV1
 */
abstract contract DataLiquidityPoolStorage is IDataLiquidityPool {
    address internal _trustedForwarder;
    string public override name;
    IDataRegistry public override dataRegistry;
    IERC20 public override token;
    string public override publicKey;
    string public override proofInstruction;
    uint256 public override totalContributorsRewardAmount;
    uint256 public override fileRewardFactor;
    address public dataDAO;
    // mapping(bytes32 => uint256) public datasetContributionsCount;

    mapping(uint256  => File ) internal _files;
    EnumerableSet.UintSet internal _filesList;

    uint256 public override contributorsCount;
    mapping(uint256  => address ) internal _contributors;
    mapping(address  => Contributor ) internal _contributorInfo;

    // ITeePool public override teePool;
}