// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./ITreasurer.sol";
import "./IFeesManager.sol";
import "./IDisburser.sol";
import "./IRightsCustodial.sol";
import "./IRightsDealBroker.sol";
import "./IRightsPolicyController.sol";
import "./IRightsCustodialGranter.sol";
import "./IRightsAccessController.sol";
import "./IRightsPolicyControllerRevoker.sol";
import "./IRightsPolicyControllerAuthorizer.sol";
import "./IContentVault.sol";

interface IRightsManager is
    ITreasurer,
    IDisburser,
    IFeesManager,
    IRightsCustodial,
    IRightsDealBroker,
    IRightsAccessController,
    IRightsCustodialGranter,
    IRightsPolicyController,
    IRightsPolicyControllerRevoker,
    IRightsPolicyControllerAuthorizer
{
    /// @notice Checks if the content is eligible for distribution by the content holder's custodial.
    /// @dev This function verifies whether the specified content can be distributed, based on the status of the custodial rights
    ///      and the content's activation state in related contracts.
    /// @param contentId The ID of the content to check for distribution eligibility.
    /// @param contentHolder The address of the content holder whose custodial rights are being checked.
    /// @return True if the content can be distributed, false otherwise.
    function isEligibleForDistribution(
        uint256 contentId,
        address contentHolder
    ) external returns (bool);
}
