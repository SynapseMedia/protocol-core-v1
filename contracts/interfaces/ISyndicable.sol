// SPDX-License-Identifier: MIT
// NatSpec format convention - https://docs.soliditylang.org/en/v0.5.10/natspec-format.html
pragma solidity ^0.8.24;

import "./IDistributor.sol";
import "./IRegistrable.sol";
import "./ITreasurer.sol";
import "./ITreasury.sol";
import "./IStatusVerifier.sol";

/// @title Content Syndication Interface
/// @notice This interface defines the functions for handling all distribution logic needed for creators and distributors.
/// @dev This interface extends ITreasurer, ITreasury, and IRegistrable interfaces.
interface ISyndicable is ITreasurer, ITreasury, IRegistrable, IStatusVerifier {
    
    /// @notice Function to set the penalty rate for quitting enrollment.
    /// @param newPenaltyRate The new penalty rate to be set. It should be a uint256 value representing a percentage (e.g., 100000000000000000 for 10%).
    /// @dev The penalty rate is a percentage (expressed as a uint256) that will be applied to the enrollment fee when a distributor quits.
    function setPenaltyRate(uint256 newPenaltyRate) external;
}