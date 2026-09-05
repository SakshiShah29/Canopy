// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {PermissionFlag, PermissionFlags} from
    "v4-periphery/src/hooks/permissionedPools/libraries/PermissionFlags.sol";
import {IAllowlistChecker} from "v4-periphery/src/hooks/permissionedPools/interfaces/IAllowlistChecker.sol";
import {BaseAllowlistChecker} from "v4-periphery/src/hooks/permissionedPools/BaseAllowListChecker.sol";

import {IPermissionedRegistry} from "@ens/registry/interfaces/IPermissionedRegistry.sol";
import {RegistryRolesLib} from "@ens/registry/libraries/RegistryRolesLib.sol";

import {CanopyRoles} from "../src/checker/CanopyRoles.sol";

/// @notice Pins every upstream assumption Canopy's design rests on.
///
/// These are dependency assertions, not unit tests. Both sponsor repos are pinned submodules, so
/// a failure here means an upstream bump changed something we build on — read the diff before
/// touching this file. Verifying by compilation is the point: the spec's claims were originally
/// established by reading source, which is exactly how the `1 << 4` role collision survived.
contract DependenciesTest is Test {
    // -------------------------------------------------------------------------
    // Uniswap — PermissionFlags
    // -------------------------------------------------------------------------

    /// @dev `PermissionFlag` is a `bytes2` user-defined type, NOT a numeric one. Any `uint16`
    ///      cast fails to compile, which is the single most likely way to lose an hour on the
    ///      checker.
    function test_permissionFlagValues() public pure {
        assertEq(PermissionFlag.unwrap(PermissionFlags.NONE), bytes2(0x0000));
        assertEq(PermissionFlag.unwrap(PermissionFlags.SWAP_ALLOWED), bytes2(0x0001));
        assertEq(PermissionFlag.unwrap(PermissionFlags.LIQUIDITY_ALLOWED), bytes2(0x0002));
        assertEq(PermissionFlag.unwrap(PermissionFlags.ALL_ALLOWED), bytes2(0xFFFF));
    }

    /// @dev The global `|`, `&` and `==` operators are how the checker assembles its return value.
    function test_permissionFlagOperators() public pure {
        PermissionFlag both = PermissionFlags.SWAP_ALLOWED | PermissionFlags.LIQUIDITY_ALLOWED;
        assertEq(PermissionFlag.unwrap(both), bytes2(0x0003));

        // This is the exact containment check `PermissionsAdapter.isAllowed` performs.
        assertTrue((both & PermissionFlags.SWAP_ALLOWED) == PermissionFlags.SWAP_ALLOWED);
        assertTrue((both & PermissionFlags.LIQUIDITY_ALLOWED) == PermissionFlags.LIQUIDITY_ALLOWED);

        // A swap-only investor must NOT satisfy the liquidity gate.
        PermissionFlag swapOnly = PermissionFlags.SWAP_ALLOWED;
        assertFalse((swapOnly & PermissionFlags.LIQUIDITY_ALLOWED) == PermissionFlags.LIQUIDITY_ALLOWED);
    }

    /// @dev `checkAllowlist(address,address)` returning `PermissionFlag` is the whole integration
    ///      surface. If this signature moves, our checker is not installable.
    function test_allowlistCheckerSignature() public pure {
        assertEq(
            IAllowlistChecker.checkAllowlist.selector,
            bytes4(keccak256("checkAllowlist(address,address)")),
            "checkAllowlist signature drifted"
        );
    }

    /// @dev We inherit `BaseAllowListChecker` rather than hand-wiring ERC-165, so its
    ///      `supportsInterface` must advertise the id `PermissionsAdapter` validates against.
    function test_baseCheckerAdvertisesInterface() public {
        StubChecker checker = new StubChecker();
        assertTrue(checker.supportsInterface(type(IAllowlistChecker).interfaceId));
        assertTrue(checker.supportsInterface(0x01ffc9a7)); // ERC-165 itself
    }

    // -------------------------------------------------------------------------
    // ENS — RegistryRolesLib nybble table
    // -------------------------------------------------------------------------

    function test_registryRoleNybbles() public pure {
        assertEq(RegistryRolesLib.ROLE_REGISTRAR, 1 << 0);
        assertEq(RegistryRolesLib.ROLE_REGISTER_RESERVED, 1 << 4);
        assertEq(RegistryRolesLib.ROLE_SET_PARENT, 1 << 8);
        assertEq(RegistryRolesLib.ROLE_UNREGISTER, 1 << 12);
        assertEq(RegistryRolesLib.ROLE_RENEW, 1 << 16);
        assertEq(RegistryRolesLib.ROLE_SET_SUBREGISTRY, 1 << 20);
        assertEq(RegistryRolesLib.ROLE_SET_RESOLVER, 1 << 24);
        assertEq(RegistryRolesLib.ROLE_CAN_TRANSFER_ADMIN, (1 << 28) << 128);
        assertEq(RegistryRolesLib.ROLE_WAS_RESERVED, 1 << 32);
        assertEq(RegistryRolesLib.ROLE_SET_URI, 1 << 36);
        assertEq(RegistryRolesLib.ROLE_CAN_NAME, 1 << 120);
        assertEq(RegistryRolesLib.ROLE_UPGRADE, 1 << 124);
    }

    /// @dev The admin twin of a role is always the role shifted 128 bits.
    function test_adminTwinIsShift128() public pure {
        assertEq(RegistryRolesLib.ROLE_REGISTRAR_ADMIN, RegistryRolesLib.ROLE_REGISTRAR << 128);
        assertEq(RegistryRolesLib.ROLE_RENEW_ADMIN, RegistryRolesLib.ROLE_RENEW << 128);
        assertEq(CanopyRoles.ROLE_ELIGIBLE_SWAP_ADMIN, CanopyRoles.ROLE_ELIGIBLE_SWAP << 128);
        assertEq(CanopyRoles.ROLE_ELIGIBLE_LIQUIDITY_ADMIN, CanopyRoles.ROLE_ELIGIBLE_LIQUIDITY << 128);
    }

    // -------------------------------------------------------------------------
    // The collision guard
    // -------------------------------------------------------------------------

    /// @dev The regression test for the bug that nearly shipped. An earlier spec revision used
    ///      `1 << 4` and `1 << 8` for these roles — `ROLE_REGISTER_RESERVED` and
    ///      `ROLE_SET_PARENT`. Granting an investor "may swap" would also have granted them the
    ///      ability to reserve names and reparent registries.
    function test_canopyRolesDoNotCollideWithRegistryRoles() public pure {
        uint256[12] memory assigned = [
            RegistryRolesLib.ROLE_REGISTRAR,
            RegistryRolesLib.ROLE_REGISTER_RESERVED,
            RegistryRolesLib.ROLE_SET_PARENT,
            RegistryRolesLib.ROLE_UNREGISTER,
            RegistryRolesLib.ROLE_RENEW,
            RegistryRolesLib.ROLE_SET_SUBREGISTRY,
            RegistryRolesLib.ROLE_SET_RESOLVER,
            RegistryRolesLib.ROLE_CAN_TRANSFER_ADMIN,
            RegistryRolesLib.ROLE_WAS_RESERVED,
            RegistryRolesLib.ROLE_SET_URI,
            RegistryRolesLib.ROLE_CAN_NAME,
            RegistryRolesLib.ROLE_UPGRADE
        ];

        for (uint256 i = 0; i < assigned.length; i++) {
            // Check the roles and their admin twins in one pass: a nybble is only safe if it is
            // free in both halves of the bitmap.
            uint256 occupied = assigned[i] | (assigned[i] << 128);

            assertEq(occupied & CanopyRoles.ROLE_ELIGIBLE_SWAP, 0, "SWAP collides");
            assertEq(occupied & CanopyRoles.ROLE_ELIGIBLE_SWAP_ADMIN, 0, "SWAP_ADMIN collides");
            assertEq(occupied & CanopyRoles.ROLE_ELIGIBLE_LIQUIDITY, 0, "LIQUIDITY collides");
            assertEq(occupied & CanopyRoles.ROLE_ELIGIBLE_LIQUIDITY_ADMIN, 0, "LIQUIDITY_ADMIN collides");
        }

        // Our own two roles must also occupy distinct nybbles.
        assertEq(CanopyRoles.ROLE_ELIGIBLE_SWAP & CanopyRoles.ROLE_ELIGIBLE_LIQUIDITY, 0);
    }

    /// @dev Both roles must sit in the unassigned 10-29 nybble window.
    function test_canopyRolesAreInTheFreeNybbleWindow() public pure {
        assertEq(_nybbleIndex(CanopyRoles.ROLE_ELIGIBLE_SWAP), 16);
        assertEq(_nybbleIndex(CanopyRoles.ROLE_ELIGIBLE_LIQUIDITY), 17);
        assertEq(_nybbleIndex(CanopyRoles.ROLE_ELIGIBLE_SWAP_ADMIN), 48);
        assertEq(_nybbleIndex(CanopyRoles.ROLE_ELIGIBLE_LIQUIDITY_ADMIN), 49);
    }

    // -------------------------------------------------------------------------
    // ENS — State / Status shape
    // -------------------------------------------------------------------------

    /// @dev Compile-time proof of the struct the checker destructures. Rev 1 of the spec had
    ///      `resource` as `bytes32`; it is a `uint256`. Assigning each field with its declared
    ///      type means a shape change breaks the build rather than the demo.
    function test_stateStructShape() public pure {
        IPermissionedRegistry.State memory s;
        s.status = IPermissionedRegistry.Status.REGISTERED;
        s.expiry = uint64(0);
        s.latestOwner = address(0);
        s.tokenId = uint256(0);
        s.resource = uint256(0);

        assertEq(uint256(s.expiry), 0);
        assertEq(s.resource, 0);
    }

    /// @dev There is no `EXPIRED` member. Expiry is a `block.timestamp` comparison against
    ///      `state.expiry`, never a status check — a name past its expiry still reads as
    ///      `REGISTERED`. Getting this wrong silently disables the entire lapse demo.
    function test_statusHasNoExpiredMember() public pure {
        assertEq(uint256(IPermissionedRegistry.Status.AVAILABLE), 0);
        assertEq(uint256(IPermissionedRegistry.Status.RESERVED), 1);
        assertEq(uint256(IPermissionedRegistry.Status.REGISTERED), 2);
    }

    // -------------------------------------------------------------------------

    /// @dev Index of the single set nybble in an EAC role constant.
    function _nybbleIndex(uint256 role) private pure returns (uint256) {
        for (uint256 i = 0; i < 64; i++) {
            if (role == (1 << (i * 4))) return i;
        }
        revert("role is not a single-nybble constant");
    }
}

/// @dev Minimal concrete `BaseAllowListChecker`, used only to prove the base contract is
///      inheritable and wires ERC-165 for us.
contract StubChecker is BaseAllowlistChecker {
    function checkAllowlist(address, address) public pure override returns (PermissionFlag) {
        return PermissionFlags.NONE;
    }
}
