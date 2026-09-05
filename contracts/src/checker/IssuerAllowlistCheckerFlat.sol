// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {BaseAllowlistChecker} from "v4-periphery/src/hooks/permissionedPools/BaseAllowListChecker.sol";
import {PermissionFlag, PermissionFlags} from
    "v4-periphery/src/hooks/permissionedPools/libraries/PermissionFlags.sol";

/// @title The conventional allowlist, kept as a baseline
/// @notice A plain issuer-managed mapping from account to permission flags — how a permissioned
///         pool is gated without ENS.
///
/// @dev This exists for two reasons, and shipping it is deliberate.
///
///      **It is what the pool launches with.** The adapter takes its checker at creation, so the
///      pool goes live with this one and is switched to `ENSAllowlistChecker` in a single
///      `updateAllowListChecker` call. That switch is the demo's on-camera beat.
///
///      **It is the benchmark baseline.** Its cost profile is the opposite of ours: one storage
///      slot per investor, so the allowlist grows linearly, while a lookup is a single warm-ish
///      `SLOAD` and therefore cheaper than any hierarchy walk. We are not claiming to beat it on
///      a single read — we would lose. The comparison worth making is what each design costs to
///      *operate*:
///
///      | | flat | ENS hierarchy |
///      |---|---|---|
///      | lookup | O(1), cheapest possible | O(depth), ~17.9k/hop |
///      | storage | O(investors) | O(1) — read from the investor's own name |
///      | revoke one investor | 1 tx | let the subname lapse, or 1 tx |
///      | revoke a broker's whole book | 1 tx **per investor** | 0 tx — the broker's name expires |
///      | eligibility expires by itself | never | always |
///
///      The last two rows are the product. This contract cannot express them at any price: there
///      is nowhere to put an expiry, and no relationship between accounts, so revoking a
///      compromised broker's investors means enumerating them off-chain and sending a transaction
///      for each — assuming you still know who they are.
contract IssuerAllowlistCheckerFlat is BaseAllowlistChecker, Ownable {
    /// @notice The permissioned token this checker answers for.
    /// @dev Bound for the same reason as in `ENSAllowlistChecker`, so the two are measured on
    ///      equal terms: attaching either to an unrelated adapter must grant nothing.
    address public immutable PERMISSIONED_TOKEN;

    mapping(address account => PermissionFlag) public permissionOf;

    event PermissionSet(address indexed account, PermissionFlag permission);

    constructor(address permissionedToken, address initialOwner) Ownable(initialOwner) {
        PERMISSIONED_TOKEN = permissionedToken;
    }

    /// @notice Set one account's permissions. Pass `PermissionFlags.NONE` to revoke.
    function setPermission(address account, PermissionFlag permission) public onlyOwner {
        permissionOf[account] = permission;
        emit PermissionSet(account, permission);
    }

    /// @notice Set the same permissions for many accounts.
    /// @dev Needed to populate the 1,000- and 10,000-investor cases the gas comparison runs, and
    ///      a fair reflection of how an issuer would really operate this: in batches.
    function setPermissions(address[] calldata accounts, PermissionFlag permission) external onlyOwner {
        for (uint256 i = 0; i < accounts.length; i++) {
            setPermission(accounts[i], permission);
        }
    }

    /// @inheritdoc BaseAllowlistChecker
    function checkAllowlist(address account, address tokenAddress) public view override returns (PermissionFlag) {
        if (tokenAddress != PERMISSIONED_TOKEN) return PermissionFlags.NONE;
        return permissionOf[account];
    }
}
