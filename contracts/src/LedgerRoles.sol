// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title LedgerRoles
/// @notice Custom EAC role constants for Canopy eligibility tiers.
/// @dev Bits 64 and 68 are in the "free range" (nybbles 16–17) of the ENSv2
///      Enhanced Access Control bitmap — they do not collide with any
///      RegistryRolesLib or EACBaseRolesLib constants.
library LedgerRoles {
    /// @notice Grants swap-only access to a permissioned pool.
    uint256 internal constant ROLE_ELIGIBLE_SWAP = 1 << 64;

    /// @notice Grants liquidity-provision access to a permissioned pool.
    ///         An account with this role but NOT ROLE_ELIGIBLE_SWAP can add
    ///         liquidity but cannot swap.  In practice the issuer grants both.
    uint256 internal constant ROLE_ELIGIBLE_LIQUIDITY = 1 << 68;
}
