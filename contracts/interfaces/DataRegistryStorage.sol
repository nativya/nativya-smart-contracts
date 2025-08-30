// SPDX-License-Identifier: MIT
pragma solidity 0.8.12;

import "./IDataRegistry.sol";

/**
 * @title Storage for DataRegistry
 * @notice For future upgrades, do not change DataRegistryStorage. Create a new
 * contract which implements DataRegistryStorage
 */
abstract contract DataRegistryStorage is IDataRegistry {
    address internal _trustedForwarder;
    uint256 public override filesCount;
    mapping(uint256  => File) internal _files;
    mapping(bytes32 => uint256) internal _urlHashToFileId;

    
}