// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../interfaces/ILensModule.sol";

abstract contract LensModule is ILensModule {
    /// @inheritdoc ILensModule
    function supportsInterface(
        bytes4 interfaceID
    ) public pure virtual override returns (bool) {
        return
            interfaceID == bytes4(keccak256(abi.encodePacked("LENS_MODULE")));
    }
}
