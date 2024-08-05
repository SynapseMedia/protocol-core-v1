// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IContentVault
/// @notice Interface for a content vault that manages secured content.
/// @dev This interface defines the methods to retrieve and secure content.
interface IContentVault {
    /// @notice Retrieves the secured content for a given content ID.
    /// @dev Returns the encrypted content stored in the vault.
    /// @param contentId The ID of the content to retrieve.
    /// @return The encrypted content as a bytes array.
    function getSecuredContent(
        uint256 contentId
    ) external view returns (bytes memory);

}
