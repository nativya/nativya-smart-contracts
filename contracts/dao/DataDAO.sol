// SPDX-License-Identifier: MIT
pragma solidity 0.8.12;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/metatx/ERC2771ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/MulticallUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IFactory.sol";

/**
 * @title DataDAO
 * @notice DAO contract that manages dataset NFT minting through Ocean Protocol
 * @dev Integrates with Ocean Protocol's ERC721Factory and DataNFT contracts
 */
contract DataDAO is
    UUPSUpgradeable,
    PausableUpgradeable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    MulticallUpgradeable,
    ERC2771ContextUpgradeable
{
    using SafeERC20 for IERC20;

    bytes32 public constant MAINTAINER_ROLE = keccak256("MAINTAINER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    // Ocean Protocol contract addresses
    IFactory public oceanFactory;
    address public oceanRouter;
    IERC20 public oceanToken;
    address private _trustedForwarder;

    // Dataset NFT tracking
    struct DatasetNFT {
        uint256 datasetId;
        address nftContract;
        uint256 tokenId;
        string metadataURI;
        uint256 contributionCount;
        uint256 mintedAt;
        bool active;
    }

    mapping(uint256 => DatasetNFT) public datasetNFTs;
    mapping(address => bool) public authorizedMinters;
    
    uint256 public nftTemplateIndex = 1;

    // Events
    event DatasetNFTMinted(
        uint256 indexed datasetId,
        address indexed nftContract,
        uint256 tokenId,
        uint256 contributionCount
    );
    
    event NFTMetadataUpdated(uint256 indexed datasetId, string newMetadataURI);
    event MinterAuthorized(address indexed minter);
    event MinterRevoked(address indexed minter);

    // Errors
    error NotAuthorizedMinter();
    error DatasetNFTAlreadyExists();
    error DatasetNFTNotFound();
    error InvalidDatasetId();
    error OceanProtocolError();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() ERC2771ContextUpgradeable(address(0)) {
        _disableInitializers();
    }

    struct InitParams {
        address trustedForwarder;
        address ownerAddress;
        address oceanFactory;
        address oceanRouter;
        address oceanToken;
    }

    /**
     * @notice Initialize the DataDAO contract
     * @param params Initialization parameters
     */
    function initialize(InitParams memory params) external initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        _trustedForwarder = params.trustedForwarder;
        oceanFactory = IFactory(params.oceanFactory);
        oceanRouter = params.oceanRouter;
        oceanToken = IERC20(params.oceanToken);

        _setRoleAdmin(MAINTAINER_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(MINTER_ROLE, DEFAULT_ADMIN_ROLE);
        
        _grantRole(DEFAULT_ADMIN_ROLE, params.ownerAddress);
        _grantRole(MAINTAINER_ROLE, params.ownerAddress);
    }

    /**
     * @notice Authorize upgrade (required by UUPS)
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    // Context functions for ERC2771
    function _msgSender() internal view override(ContextUpgradeable, ERC2771ContextUpgradeable) returns (address) {
        return ERC2771ContextUpgradeable._msgSender();
    }

    function _msgData() internal view override(ContextUpgradeable, ERC2771ContextUpgradeable) returns (bytes calldata) {
        return ERC2771ContextUpgradeable._msgData();
    }

    function _contextSuffixLength() internal view override(ContextUpgradeable, ERC2771ContextUpgradeable) returns (uint256) {
        return ERC2771ContextUpgradeable._contextSuffixLength();
    }

    function trustedForwarder() public view returns (address) {
        return _trustedForwarder;
    }

    /**
     * @notice Get contract version
     */
    function version() external pure returns (uint256) {
        return 1;
    }

    // Access Control Functions

    /**
     * @notice Authorize a contract to mint dataset NFTs
     * @param minter Address to authorize (typically DataLiquidityPool)
     */
    function authorizeMinter(address minter) external onlyRole(DEFAULT_ADMIN_ROLE) {
        authorizedMinters[minter] = true;
        _grantRole(MINTER_ROLE, minter);
        emit MinterAuthorized(minter);
    }

    /**
     * @notice Revoke minter authorization
     * @param minter Address to revoke
     */
    function revokeMinter(address minter) external onlyRole(DEFAULT_ADMIN_ROLE) {
        authorizedMinters[minter] = false;
        _revokeRole(MINTER_ROLE, minter);
        emit MinterRevoked(minter);
    }

    // Ocean Protocol Integration Functions

    /**
     * @notice Mint a dataset NFT through Ocean Protocol when milestone is reached
     * @param datasetId The dataset ID that reached the milestone
     * @param contributionCount Number of contributions that triggered the mint
     */
    function mintDatasetNFT(uint256 datasetId, uint256 contributionCount) 
        external 
        whenNotPaused 
        nonReentrant
        onlyRole(MINTER_ROLE) 
    {
        if (datasetNFTs[datasetId].active) {
            revert DatasetNFTAlreadyExists();
        }

        // Create NFT and ERC20 through Ocean Protocol
        (address nftContract, address erc20Contract) = _createNFTWithERC20(datasetId, contributionCount);

        // Store the dataset NFT information
        datasetNFTs[datasetId] = DatasetNFT({
            datasetId: datasetId,
            nftContract: nftContract,
            tokenId: 1,
            metadataURI: _generateMetadataURI(datasetId, contributionCount),
            contributionCount: contributionCount,
            mintedAt: block.timestamp,
            active: true
        });

        emit DatasetNFTMinted(datasetId, nftContract, 1, contributionCount);
    }

    /**
     * @notice Internal function to create NFT with ERC20 through Ocean Protocol
     * @param datasetId The dataset ID
     * @param contributionCount Number of contributions
     * @return nftContract Address of created NFT contract
     * @return erc20Contract Address of created ERC20 contract
     */
    function _createNFTWithERC20(uint256 datasetId, uint256 contributionCount) 
        internal 
        returns (address nftContract, address erc20Contract) 
    {
        // Prepare NFT creation data
        IFactory.NftCreateData memory nftData = _prepareNFTData(datasetId, contributionCount);
        
        // Prepare ERC20 creation data
        IFactory.ErcCreateData memory ercData = _prepareERC20Data(datasetId);

        try oceanFactory.createNftWithErc20(nftData, ercData) returns (
            address _nftContract, 
            address _erc20Contract
        ) {
            return (_nftContract, _erc20Contract);
        } catch {
            revert OceanProtocolError();
        }
    }

    /**
     * @notice Prepare NFT creation data
     * @param datasetId The dataset ID
     * @param contributionCount Number of contributions
     * @return nftData NFT creation data
     */
    function _prepareNFTData(uint256 datasetId, uint256 contributionCount) 
        internal 
        view 
        returns (IFactory.NftCreateData memory nftData) 
    {
        string memory metadataURI = _generateMetadataURI(datasetId, contributionCount);
        string memory nftName = string(abi.encodePacked("DataDAO Dataset #", _toString(datasetId)));
        string memory nftSymbol = string(abi.encodePacked("DDAO", _toString(datasetId)));

        return IFactory.NftCreateData({
            name: nftName,
            symbol: nftSymbol,
            templateIndex: nftTemplateIndex,
            tokenURI: metadataURI,
            transferable: false,
            owner: address(this)
        });
    }

    /**
     * @notice Prepare ERC20 creation data
     * @param datasetId The dataset ID
     * @return ercData ERC20 creation data
     */
    function _prepareERC20Data(uint256 datasetId) 
        internal 
        view 
        returns (IFactory.ErcCreateData memory ercData) 
    {
        string[] memory strings = new string[](2);
        strings[0] = string(abi.encodePacked("Data Token ", _toString(datasetId)));
        strings[1] = string(abi.encodePacked("DT", _toString(datasetId)));
        
        address[] memory addresses = new address[](3);
        addresses[0] = address(this);
        addresses[1] = address(0);
        addresses[2] = address(this);
        
        uint256[] memory uints = new uint256[](2);
        uints[0] = 1000000000000000000;
        uints[1] = 0;
        
        bytes[] memory bytess = new bytes[](0);

        return IFactory.ErcCreateData({
            templateIndex: 1,
            strings: strings,
            addresses: addresses,
            uints: uints,
            bytess: bytess
        });
    }

    // Pause Functions
    function pause() external onlyRole(MAINTAINER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(MAINTAINER_ROLE) {
        _unpause();
    }

    // View Functions

    /**
     * @notice Get dataset NFT information
     * @param datasetId The dataset ID
     * @return DatasetNFT struct
     */
    function getDatasetNFT(uint256 datasetId) external view returns (DatasetNFT memory) {
        return datasetNFTs[datasetId];
    }

    /**
     * @notice Check if dataset has minted NFT
     * @param datasetId The dataset ID
     * @return bool indicating if NFT exists
     */
    function hasDatasetNFT(uint256 datasetId) external view returns (bool) {
        return datasetNFTs[datasetId].active;
    }

    /**
     * @notice Generate metadata URI for dataset NFT
     * @param datasetId The dataset ID
     * @param contributionCount Number of contributions
     * @return metadataURI Generated metadata URI
     */
    function _generateMetadataURI(uint256 datasetId, uint256 contributionCount) 
        internal 
        pure 
        returns (string memory) 
    {
        return string(abi.encodePacked(
            "https://metadata.datadao.org/dataset/",
            _toString(datasetId),
            "/contributions/",
            _toString(contributionCount)
        ));
    }

    /**
     * @notice Convert uint256 to string
     * @param value The number to convert
     * @return String representation
     */
    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}