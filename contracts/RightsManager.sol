// SPDX-License-Identifier: MIT
// NatSpec format convention - https://docs.soliditylang.org/en/v0.5.10/natspec-format.html
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "contracts/base/upgradeable/LedgerUpgradeable.sol";
import "contracts/base/upgradeable/FeesManagerUpgradeable.sol";
import "contracts/base/upgradeable/TreasurerUpgradeable.sol";
import "contracts/base/upgradeable/CurrencyManagerUpgradeable.sol";
import "contracts/base/upgradeable/GovernableUpgradeable.sol";
import "contracts/base/upgradeable/extensions/RightsManagerContentAccessUpgradeable.sol";
import "contracts/base/upgradeable/extensions/RightsManagerCustodialUpgradeable.sol";
import "contracts/base/upgradeable/extensions/RightsManagerPolicyControllerUpgradeable.sol";
import "contracts/interfaces/IRegistrableVerifiable.sol";
import "contracts/interfaces/IReferendumVerifiable.sol";
import "contracts/interfaces/IRightsManager.sol";
import "contracts/interfaces/IPolicy.sol";
import "contracts/interfaces/IDistributor.sol";
import "contracts/interfaces/IOwnership.sol";
import "contracts/interfaces/IRepository.sol";
import "contracts/libraries/TreasuryHelper.sol";
import "contracts/libraries/FeesHelper.sol";
import "contracts/libraries/Constants.sol";
import "contracts/libraries/Types.sol";

/// @title Rights Manager
/// @notice This contract manages digital rights, allowing content holders to set prices, rent content, etc.
/// @dev This contract uses the UUPS upgradeable pattern and is initialized using the `initialize` function.
contract RightsManager is
    Initializable,
    UUPSUpgradeable,
    LedgerUpgradeable,
    FeesManagerUpgradeable,
    GovernableUpgradeable,
    TreasurerUpgradeable,
    ReentrancyGuardUpgradeable,
    CurrencyManagerUpgradeable,
    RightsManagerCustodialUpgradeable,
    RightsManagerContentAccessUpgradeable,
    RightsManagerPolicyControllerUpgradeable,
    IRightsManager
{
    using TreasuryHelper for address;
    using FeesHelper for uint256;

    /// @notice Emitted when distribution custodial rights are granted to a distributor.
    /// @param prevCustody The previous distributor custodial address.
    /// @param newCustody The new distributor custodial address.
    /// @param contentId The content identifier.
    event GrantedCustodial(
        address indexed prevCustody,
        address indexed newCustody,
        uint256 contentId
    );

    event FeesDisbursed(
        address indexed treasury,
        uint256 amount,
        address currency
    );

    event GrantedAccess(address account, uint256 contentId);
    event RightsDelegated(address indexed policy, uint256 contentId);
    event RightsRevoked(address indexed policy, uint256 contentId);

    /// KIM: any initialization here is ephimeral and not included in bytecode..
    /// so the code within a logic contract’s constructor or global declaration
    /// will never be executed in the context of the proxy’s state
    /// https://docs.openzeppelin.com/upgrades-plugins/1.x/proxies#the-constructor-caveat
    IRegistrableVerifiable private syndication;
    IReferendumVerifiable private referendum;
    IOwnership private ownership;

    /// @dev Error that is thrown when a restricted access to the holder is attempted.
    error RestrictedAccessToHolder();
    /// @dev Error that is thrown when a content hash is already registered.
    error InvalidInactiveDistributor();
    error InvalidNotAllowedContent();
    error InvalidUnknownContent();
    error InvalidAccessValidation(string reason);
    error InvalidAlreadyRegisteredContent();
    error NoFundsToWithdraw(address);
    error NoDeal(string reason);

    /// @dev Constructor that disables initializers to prevent the implementation contract from being initialized.
    /// https://forum.openzeppelin.com/t/uupsupgradeable-vulnerability-post-mortem/15680
    /// https://forum.openzeppelin.com/t/what-does-disableinitializers-function-mean/28730/5
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract with the given dependencies.
    /// @param repository The contract registry to retrieve needed contracts instance.
    /// @param initialFee The initial fee for the treasury in basis points (bps).
    /// @dev This function is called only once during the contract deployment.
    function initialize(
        address repository,
        uint256 initialFee
    ) public initializer onlyBasePointsAllowed(initialFee) {
        __Ledger_init();
        __Governable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __CurrencyManager_init();
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());

        // initialize dependencies for RM
        IRepository repo = IRepository(repository);
        address treasuryAddress = repo.getContract(T.ContractTypes.TRE);
        address ownershipAddress = repo.getContract(T.ContractTypes.OWN);
        address syndicationAddress = repo.getContract(T.ContractTypes.SYN);
        address referendumAddress = repo.getContract(T.ContractTypes.REF);

        ownership = IOwnership(ownership);
        syndication = IRegistrableVerifiable(syndicationAddress);
        referendum = IReferendumVerifiable(referendumAddress);

        __Fees_init(initialFee, address(0));
        __Treasurer_init(treasuryAddress);
    }

    /// @dev Authorizes the upgrade of the contract.
    /// @notice Only the owner can authorize the upgrade.
    /// @param newImplementation The address of the new implementation contract.
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyAdmin {}

    /// @notice Checks if the given distributor is active and not blocked.
    /// @param distributor The address of the distributor to check.
    /// @return True if the distributor is active, false otherwise.
    function _checkActiveDistributor(
        address distributor
    ) private returns (bool) {
        return syndication.isActive(distributor); // is active status in syndication
    }

    /// @notice Checks if the given content is active and not blocked.
    /// @param contentId The ID of the content to check.
    /// @return True if the content is active, false otherwise.
    function _checkActiveContent(
        uint256 contentId
    ) private view returns (bool) {
        return referendum.isActive(contentId); // is active in referendum
    }

    /// @notice Allocates the specified amount across a distribution array and returns the remaining unallocated amount.
    /// @dev Distributes the amount based on the provided distribution array.
    /// @param amount The total amount to be allocated.
    /// @param currency The address of the currency being allocated.
    /// @param splits An array of Splits structs specifying the split percentages and target addresses.
    /// @return The remaining unallocated amount after distribution.
    function _allocate(
        uint256 amount,
        address currency,
        T.Shares[] memory splits
    ) private returns (uint256) {
        // Ensure there's a distribution or return the full amount.
        if (splits.length == 0) return amount;
        if (splits.length > 100) {
            revert NoDeal(
                "Invalid split allocations. Cannot be more than 100."
            );
        }

        uint8 i = 0;
        uint256 accBps = 0; // accumulated base points
        uint256 accTotal = 0; // accumulated total allocation

        while (i < splits.length) {
            // Retrieve base points and target address from the distribution array.
            uint256 bps = splits[i].bps;
            address target = splits[i].target;
            // safely increment i uncheck overflow
            unchecked {
                ++i;
            }

            if (bps == 0) continue;
            // Calculate and register the allocation for each distribution.
            uint256 registeredAmount = amount.perOf(bps);
            _sumLedgerEntry(target, registeredAmount, currency);

            accTotal += registeredAmount;
            accBps += bps;
        }

        // Ensure the total base points do not exceed the maximum allowed (100%).
        if (accBps > C.BPS_MAX)
            revert NoDeal("Invalid split base points overflow.");
        return amount - accTotal; // Return the remaining unallocated amount.
    }

    /// @notice Modifier to restrict access to the holder only or their delegate.
    /// @param contentId The content hash to give distribution rights.
    /// @dev Only the holder of the content can pass this validation.
    modifier onlyHolder(uint256 contentId) {
        if (ownership.ownerOf(contentId) != _msgSender())
            revert RestrictedAccessToHolder();
        _;
    }

    /// @notice Modifier to check if the content is registered.
    /// @param contentId The content hash to check.
    modifier onlyRegisteredContent(uint256 contentId) {
        if (ownership.ownerOf(contentId) == address(0))
            revert InvalidUnknownContent();
        _;
    }

    /// @notice Modifier to check if the distributor is active and not blocked.
    /// @param distributor The distributor address to check.
    modifier onlyActiveDistributor(address distributor) {
        if (!_checkActiveDistributor(distributor))
            revert InvalidInactiveDistributor();
        _;
    }

    /// @inheritdoc IFeesManager
    /// @notice Sets a new treasury fee for a specific currency.
    /// @param newTreasuryFee The new fee amount to be set.
    /// @param currency The currency to associate fees with. Use address(0) for the native coin.
    function setFees(
        uint256 newTreasuryFee,
        address currency
    )
        external
        onlyGov
        onlyValidCurrency(currency)
        onlyBasePointsAllowed(newTreasuryFee)
    {
        _setFees(newTreasuryFee, currency);
        _addCurrency(currency);
    }

    /// @inheritdoc IFeesManager
    /// @notice Sets a new treasury fee for the native coin.
    /// @param newTreasuryFee The new fee amount to be set.
    function setFees(
        uint256 newTreasuryFee
    ) external onlyGov onlyBasePointsAllowed(newTreasuryFee) {
        _setFees(newTreasuryFee, address(0));
        _addCurrency(address(0));
    }

    /// @inheritdoc ITreasurer
    /// @notice Sets the address of the treasury.
    /// @param newTreasuryAddress The new treasury address to be set.
    /// @dev Only callable by the governance role.
    function setTreasuryAddress(address newTreasuryAddress) external onlyGov {
        _setTreasuryAddress(newTreasuryAddress);
    }

    /// @inheritdoc IDisburser
    /// @notice Disburses funds from the contract to a specified address.
    /// @param amount The amount of currencies to disburse.
    /// @param currency The address of the ERC20 token to disburse tokens.
    /// @dev This function can only be called by governance or an authorized entity.
    function disburse(
        uint256 amount,
        address currency
    ) external onlyGov onlyValidCurrency(currency) {
        address treasury = getTreasuryAddress();
        treasury.transfer(amount, currency);
        emit FeesDisbursed(treasury, amount, currency);
    }

    /// @inheritdoc IDisburser
    /// @notice Disburses funds from the contract to a specified address.
    /// @param amount The amount of coins to disburse.
    /// @dev This function can only be called by governance or an authorized entity.
    function disburse(uint256 amount) external onlyGov {
        // collect native coins and send it to treasury
        address treasury = getTreasuryAddress();
        // if no balance revert..
        treasury.transfer(amount);
        emit FeesDisbursed(treasury, amount, address(0));
    }

    /// @inheritdoc IFundsManager
    /// @notice Withdraws funds from the contract to a specified recipient's address.
    /// @param amount The amount of funds to withdraw.
    /// @param currency The address of the ERC20 token to withdraw, or address(0) to withdraw native coins.
    function withdraw(
        uint256 amount,
        address currency
    ) external onlyValidCurrency(currency) {
        address recipient = _msgSender();
        uint256 available = getLedgerEntry(recipient, currency);
        if (available < amount) revert NoFundsToWithdraw(recipient);

        recipient.transfer(amount, currency);
        _subLedgerEntry(recipient, amount, currency);
    }

    /// @inheritdoc IRightsManager
    /// @notice Checks if the content is eligible for distribution.
    /// @param contentId The ID of the content.
    /// @return True if the content can be distributed, false otherwise.
    function isEligibleForDistribution(
        uint256 contentId
    ) public returns (bool) {
        // Perform checks to ensure the content/distributor has not been blocked.
        // Check if the content's custodial is active in the Syndication contract
        // and if the content is active in the Referendum contract.
        return
            _checkActiveDistributor(getCustody(contentId)) &&
            _checkActiveContent(contentId);
    }

    /// @inheritdoc IRightsPolicyControllerAuthorizer
    /// @notice Grants operational rights for a specific content ID to a policy.
    /// @param policy The address of the policy contract to which the rights are being granted.
    /// @param contentId The ID of the content for which the rights are being granted.
    function grantRights(
        address policy,
        uint256 contentId
    )
        external
        onlyHolder(contentId)
        onlyRegisteredContent(contentId)
        onlyPolicyContract(policy)
    {
        _delegateRights(policy, contentId);
        emit RightsDelegated(policy, contentId);
    }

    /// @inheritdoc IRightsPolicyControllerRevoker
    /// @notice Revokes operational rights for a specific policy related to a content ID.
    /// @param policy The address of the policy contract for which rights are being revoked.
    /// @param contentId The ID of the content associated with the policy being revoked.
    function revokeRights(
        address policy,
        uint256 contentId
    )
        external
        onlyHolder(contentId)
        onlyRegisteredContent(contentId)
        onlyPolicyContract(policy)
    {
        _revokeRights(policy, contentId);
        emit RightsRevoked(policy, contentId);
    }

    /// @inheritdoc IRightsCustodialGranter
    /// @notice Grants custodial rights for the content to a distributor.
    /// @param distributor The address of the distributor.
    /// @param contentId The content ID to grant custodial rights for.
    function grantCustody(
        uint256 contentId,
        address distributor
    )
        external
        onlyActiveDistributor(distributor)
        onlyRegisteredContent(contentId)
        onlyHolder(contentId)
    {
        // if it's first custody assignment prev = address(0)
        address prevCustody = getCustody(contentId);
        _grantCustody(distributor, contentId);
        emit GrantedCustodial(prevCustody, distributor, contentId);
    }

    /// @inheritdoc IRightsAccessController
    /// @notice Enforces access for a specific account to a content ID based on the conditions set by a policy.
    /// @dev This function is intended to be called only by the policy contracts (`IPolicy`)
    ///      themselves, functioning as a self-executing mechanism for policies.
    ///      It handles the transaction processing, fee negotiation, and distribution of payouts
    ///      according to the terms defined by the policy.
    /// @param account The address of the account to be granted access to the content.
    /// @param contentId The unique identifier of the content for which access is being registered.
    function grantAccess(
        uint256 contentId,
        address account
    )
        external
        payable
        nonReentrant
        onlyRegisteredContent(contentId)
        onlyWhenPolicyAuthorized(_msgSender(), contentId)
    {
        // in some cases the content or distributor could be revoked..
        if (!isEligibleForDistribution(contentId))
            revert InvalidNotAllowedContent();

        address policyAddress = _msgSender();
        IPolicy policy = IPolicy(policyAddress);
        T.Payouts memory alloc = policy.payouts(account, contentId);

        address custodial = getCustody(contentId);
        uint256 custodials = getCustodyCount(custodial);
        IDistributor distributor = IDistributor(custodial);
        // The delegated policy must ensure that the necessary steps
        // are taken to handle the transaction value or set the appropriate
        // approve/allowance for the RM (Rights Management) contract.
        uint256 amount = alloc.t9n.amount;
        address currency = alloc.t9n.currency;
        uint256 total = policyAddress.safeDeposit(amount, currency);
        //!IMPORTANT if distributor or trasury does not support the currency, will revert..
        // the max bps integrity is warrantied by treasure fees
        uint256 treasury = total.perOf(getFees(currency)); // bps
        uint256 accepted = distributor.negotiate(total, currency, custodials);
        uint256 deductions = treasury + accepted;

        if (deductions > total) revert NoDeal("The fees are too high.");
        uint256 remaining = _allocate(total - deductions, currency, alloc.s4s);
        // register split distribution in ledger..
        _sumLedgerEntry(ownership.ownerOf(contentId), remaining, currency);
        _sumLedgerEntry(distributor.getManager(), accepted, currency);
        _registerPolicy(account, contentId, policyAddress);
        emit GrantedAccess(account, contentId);
    }
}
