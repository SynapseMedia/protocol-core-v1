// SPDX-License-Identifier: MIT
// NatSpec format convention - https://docs.soliditylang.org/en/v0.5.10/natspec-format.html
pragma solidity 0.8.26;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { GovernableUpgradeable } from "contracts/base/upgradeable/GovernableUpgradeable.sol";

import { IRightsPolicyAuthorizer } from "contracts/interfaces/rightsmanager/IRightsPolicyAuthorizer.sol";
import { IPolicyAuditorVerifiable } from "contracts/interfaces/policies/IPolicyAuditorVerifiable.sol";

contract RightsPolicyAuthorizer is Initializable, UUPSUpgradeable, GovernableUpgradeable, IRightsPolicyAuthorizer {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// KIM: any initialization here is ephimeral and not included in bytecode..
    /// so the code within a logic contract’s constructor or global declaration
    /// will never be executed in the context of the proxy’s state
    /// https://docs.openzeppelin.com/upgrades-plugins/1.x/proxies#the-constructor-caveat

    /// Preventing accidental/malicious changes during contract reinitializations.
    IPolicyAuditorVerifiable public immutable POLICY_AUDIT;

    /// @dev Mapping to store the delegated rights for each policy contract (address)
    /// by each content holder (address).
    mapping(address => EnumerableSet.AddressSet) private delegation;
    /// @notice Emitted when rights are granted to a policy for content.
    /// @param policy The policy contract address granted rights.
    /// @param holder The address of the content rights holder.
    event RightsGranted(address indexed policy, address holder);
    /// @notice Emitted when rights are revoked from a policy for content.
    /// @param policy The policy contract address whose rights are being revoked.
    /// @param holder The address of the content rights holder.
    event RightsRevoked(address indexed policy, address holder);

    /// @dev Error thrown when a policy has not been audited or approved for operation.
    /// @param policy The address of the unaudited policy.
    error InvalidNotAuditedPolicy(address policy);
    /// @dev Error thrown when there is an issue with the policy setup.
    /// @param reason A string explaining the reason for the invalid policy setup.
    error InvalidPolicySetup(string reason);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address policyAudit) {
        /// https://forum.openzeppelin.com/t/uupsupgradeable-vulnerability-post-mortem/15680
        /// https://forum.openzeppelin.com/t/what-does-disableinitializers-function-mean/28730/5
        _disableInitializers();
        // audit contract to validate the approval from mods
        POLICY_AUDIT = IPolicyAuditorVerifiable(policyAudit);
    }

    /// @notice Initializes the proxy state.
    function initialize() public initializer {
        __UUPSUpgradeable_init();
        __Governable_init(msg.sender);
    }

    /// @notice Initializes and authorizes a policy contract for content held by the holder.
    /// @param policy The address of the policy contract to be initialized and authorized.
    function authorizePolicy(address policy) external {
        // only valid and audit polices are allowed to be authorized and initialized..
        if (!_isValidPolicy(policy)) revert InvalidNotAuditedPolicy(policy);
        delegation[msg.sender].add(policy);
        emit RightsGranted(policy, msg.sender);
    }

    /// @notice Revokes the delegation of rights to a policy contract.
    /// @param policy The address of the policy contract whose rights delegation is being revoked.
    function revokePolicy(address policy) external {
        delegation[msg.sender].remove(policy);
        emit RightsRevoked(policy, msg.sender);
    }

    /// @dev Verify if the specified policy contract has been delegated the rights by the content holder.
    /// @param policy The address of the policy contract to check for delegation.
    /// @param holder The content rights holder to check for delegation.
    function isPolicyAuthorized(address policy, address holder) public view returns (bool) {
        return delegation[holder].contains(policy) && _isValidPolicy(policy);
    }

    /// @notice Retrieves all policies authorized by a specific content holder.
    /// @dev This function returns an array of policy addresses that have been granted rights by the holder.
    /// @param holder The address of the content rights holder whose authorized policies are being queried.
    function getAuthorizedPolicies(address holder) public view returns (address[] memory) {
        // https://docs.openzeppelin.com/contracts/5.x/api/utils#EnumerableSet-values-struct-EnumerableSet-AddressSet-
        // This operation will copy the entire storage to memory, which can be quite expensive.
        // This function is designed to be used primarily as a view accessor, queried without any gas fees.
        // Developers should note that this function has an unbounded cost, and using it as part of a state-changing
        // function may render the function uncallable if the set grows to a point where copying to memory
        /// consumes too much gas to fit in a block.
        return delegation[holder].values();
    }

    /// @dev Authorizes the upgrade of the contract.
    /// @notice Only the owner can authorize the upgrade.
    /// @param newImplementation The address of the new implementation contract.
    function _authorizeUpgrade(address newImplementation) internal override onlyAdmin {}

    /// @notice Verifies whether a given policy is valid.
    /// @dev The function ensures that the policy address is not the zero address
    ///      and that the policy has been audited.
    /// @param policy The address of the policy contract to verify.
    function _isValidPolicy(address policy) private view returns (bool) {
        return (policy != address(0) && POLICY_AUDIT.isAudited(policy));
    }
}
