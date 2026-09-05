// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title Canopy's eligibility roles in ENS Enhanced Access Control's nybble bitmap
/// @notice Granted on an investor's subname resource, read by `ENSAllowlistChecker`.
///
/// @dev Nybbles 16/17 are chosen because `RegistryRolesLib` already owns 0-9, 30, 31 and their
///      admin twins; only 10-29 is free. Our admin twins land on 48/49, also free.
///      `test/Dependencies.t.sol` guards this against upstream drift.
///
/// @dev Never grant on `ROOT_RESOURCE`: a nybble is a 4-bit *counter*, so a shared resource caps
///      the product at 15 investors. Granting per-subname is also what gives us the expiry cascade.
library CanopyRoles {
    /// @dev Nybble 16. Investor may swap through the permissioned pool.
    uint256 internal constant ROLE_ELIGIBLE_SWAP = 1 << 64;

    /// @dev Nybble 48. Authorizes granting `ROLE_ELIGIBLE_SWAP`.
    uint256 internal constant ROLE_ELIGIBLE_SWAP_ADMIN = ROLE_ELIGIBLE_SWAP << 128;

    /// @dev Nybble 17. Investor may add liquidity to the permissioned pool.
    uint256 internal constant ROLE_ELIGIBLE_LIQUIDITY = 1 << 68;

    /// @dev Nybble 49. Authorizes granting `ROLE_ELIGIBLE_LIQUIDITY`.
    uint256 internal constant ROLE_ELIGIBLE_LIQUIDITY_ADMIN = ROLE_ELIGIBLE_LIQUIDITY << 128;
}
