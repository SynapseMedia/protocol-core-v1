// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "contracts/base/upgradeable/CurrencyManagerUpgradeable.sol";
import "contracts/base/upgradeable/FeesManagerUpgradeable.sol";
import "contracts/libraries/TreasuryHelper.sol";
import "contracts/interfaces/IDistributor.sol";

/// @title Content Distributor contract.
/// @notice Use this contract to handle all needed logic for distributors.
/// @dev This contract inherits from Ownable and ERC165, and implements the IDistributor interface.
/// Extending upgradeable contracts in a non-upgradeable contract to extend ERC-7201: Namespaced Storage Layout
/// Same as below with __gap the issue could happen using this contract as implementation and receiving delegated calls.
/// This contract can be deployed without needing to upgrade.
contract Distributor is
    Initializable,
    ERC165Upgradeable,
    OwnableUpgradeable,
    FeesManagerUpgradeable,
    CurrencyManagerUpgradeable,
    IDistributor
{
    using TreasuryHelper for address;

    /// @notice The URL to the distribution.
    /// Since this is a contract considered as implementation for beacon proxy,
    /// we need to reserve a gap for endpoint to avoid memory layout getting mixed up.
    /// https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable
    string private endpoint;

    /// @notice Event emitted when the endpoint is updated.
    /// @param oldEndpoint The old endpoint.
    /// @param newEndpoint The new endpoint.
    event EndpointUpdated(string oldEndpoint, string newEndpoint);

    /// @notice Error to be thrown when an invalid endpoint is provided.
    error InvalidEndpoint();

    /// @notice Constructor to initialize the Distributor contract.
    function initialize(
        string memory _endpoint,
        address _owner
    ) public initializer {
        __ERC165_init();
        __Ownable_init(_owner);
        __CurrencyManager_init();
        __Fees_init(1, address(0));

        if (bytes(_endpoint).length == 0) revert InvalidEndpoint();
        endpoint = _endpoint;
    }

    /// @inheritdoc IDistributor
    /// @notice Gets the manager of the distributor, which is the owner of the contract.
    /// @return The address of the manager (owner) of the contract.
    function getManager() public view returns (address) {
        return owner();
    }

    /// @inheritdoc IDistributor
    /// @notice Gets the current distribution endpoint URL.
    /// @return The endpoint URL as a string.
    function getEndpoint() external view returns (string memory) {
        return endpoint;
    }

    /// @inheritdoc IDistributor
    /// @notice Updates the distribution endpoint URL.
    /// @param _endpoint The new endpoint URL to be set.
    /// @dev This function reverts if the provided endpoint is an empty string.
    /// @dev Emits an {EndpointUpdated} event.
    function updateEndpoint(string calldata _endpoint) external onlyOwner {
        if (bytes(_endpoint).length == 0) revert InvalidEndpoint();
        string memory oldEndpoint = endpoint;
        endpoint = _endpoint;
        emit EndpointUpdated(oldEndpoint, _endpoint);
    }

    /// @inheritdoc IFeesManager
    /// @notice Sets a new treasury fee for a specific token.
    /// @param newTreasuryFee The new fee expresed as base points to be set.
    /// @param token The address of the token for which the fee is to be set.
    function setFees(
        uint256 newTreasuryFee,
        address token
    ) public onlyOwner onlyBasePointsAllowed(newTreasuryFee) {
        _setFees(newTreasuryFee, token);
        _addCurrency(token);
    }

    /// @inheritdoc IFeesManager
    /// @notice Sets a new treasury fee for the native token.
    /// @param newTreasuryFee The new fee expresed as base points to be set.
    function setFees(
        uint256 newTreasuryFee
    ) public onlyOwner onlyBasePointsAllowed(newTreasuryFee) {
        _setFees(newTreasuryFee, address(0));
        _addCurrency(address(0));
    }

    /// @inheritdoc IDisburser
    /// @notice Withdraws the specified amount of native tokens from the contract.
    /// @param amount The amount of native tokens to withdraw.
    function withdraw(uint256 amount) public override onlyOwner {
        // withdraw native token if supported
        owner().disburst(amount);
    }

    /// @inheritdoc IDisburser
    /// @notice Withdraws the specified amount of ERC20 tokens from the contract.
    /// @param amount The amount of ERC20 tokens to withdraw.
    /// @param token The address of the ERC20 token to withdraw.
    function withdraw(uint256 amount, address token) public onlyOwner {
        owner().disburst(amount, token);
    }

    /// @inheritdoc IERC165
    /// @notice Checks if the contract supports a specific interface.
    /// @param interfaceId The interface identifier to check.
    /// @return True if the interface is supported, otherwise false.
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override returns (bool) {
        return
            interfaceId == type(IDistributor).interfaceId ||
            super.supportsInterface(interfaceId);
    }

}
