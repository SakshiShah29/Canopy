// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

import {IAllowlistChecker} from "v4-periphery/src/hooks/permissionedPools/interfaces/IAllowlistChecker.sol";
import {PermissionFlag, PermissionFlags} from
    "v4-periphery/src/hooks/permissionedPools/libraries/PermissionFlags.sol";

import {IssuerAllowlistCheckerFlat} from "../src/checker/IssuerAllowlistCheckerFlat.sol";

contract IssuerAllowlistCheckerFlatTest is Test {
    IssuerAllowlistCheckerFlat internal checker;

    address internal constant TOKEN = address(0xC0FFEE);
    address internal constant ISSUER = address(0xB055);
    address internal constant ALICE = address(0xA11CE);
    address internal constant MM = address(0xFEED);
    address internal constant STRANGER = address(0x5747A);

    function setUp() public {
        checker = new IssuerAllowlistCheckerFlat(TOKEN, ISSUER);
    }

    function _assertFlag(PermissionFlag actual, PermissionFlag expected) internal pure {
        assertEq(PermissionFlag.unwrap(actual), PermissionFlag.unwrap(expected));
    }

    /// @dev The gate that decides whether the pool can launch at all.
    ///      `PermissionsAdapter._updateAllowListChecker` runs exactly this and reverts
    ///      `InvalidAllowListChecker` if it fails, so a checker that misses it cannot be supplied
    ///      to `createPermissionsAdapter` — and the failure surfaces at adapter creation, far from
    ///      its cause.
    function test_isInstallableOnAnAdapter() public view {
        assertTrue(ERC165Checker.supportsInterface(address(checker), type(IAllowlistChecker).interfaceId));
    }

    function test_defaultsToNone() public view {
        _assertFlag(checker.checkAllowlist(ALICE, TOKEN), PermissionFlags.NONE);
    }

    function test_issuerGrantsSwapOnly() public {
        vm.prank(ISSUER);
        checker.setPermission(ALICE, PermissionFlags.SWAP_ALLOWED);

        _assertFlag(checker.checkAllowlist(ALICE, TOKEN), PermissionFlags.SWAP_ALLOWED);

        // The tier split, evaluated the way the adapter evaluates it.
        PermissionFlag flag = checker.checkAllowlist(ALICE, TOKEN);
        assertTrue((flag & PermissionFlags.SWAP_ALLOWED) == PermissionFlags.SWAP_ALLOWED);
        assertFalse((flag & PermissionFlags.LIQUIDITY_ALLOWED) == PermissionFlags.LIQUIDITY_ALLOWED);
    }

    function test_issuerGrantsBothTiers() public {
        vm.prank(ISSUER);
        checker.setPermission(MM, PermissionFlags.SWAP_ALLOWED | PermissionFlags.LIQUIDITY_ALLOWED);

        _assertFlag(checker.checkAllowlist(MM, TOKEN), PermissionFlags.SWAP_ALLOWED | PermissionFlags.LIQUIDITY_ALLOWED);
    }

    function test_revokeIsAnExplicitTransaction() public {
        vm.startPrank(ISSUER);
        checker.setPermission(ALICE, PermissionFlags.SWAP_ALLOWED);
        checker.setPermission(ALICE, PermissionFlags.NONE);
        vm.stopPrank();

        _assertFlag(checker.checkAllowlist(ALICE, TOKEN), PermissionFlags.NONE);
    }

    function test_bulkGrant() public {
        address[] memory accounts = new address[](3);
        accounts[0] = ALICE;
        accounts[1] = MM;
        accounts[2] = STRANGER;

        vm.prank(ISSUER);
        checker.setPermissions(accounts, PermissionFlags.SWAP_ALLOWED);

        for (uint256 i = 0; i < accounts.length; i++) {
            _assertFlag(checker.checkAllowlist(accounts[i], TOKEN), PermissionFlags.SWAP_ALLOWED);
        }
    }

    function test_deniesForAnUnrelatedToken() public {
        vm.prank(ISSUER);
        checker.setPermission(ALICE, PermissionFlags.SWAP_ALLOWED);

        _assertFlag(checker.checkAllowlist(ALICE, address(0xBEEF)), PermissionFlags.NONE);
    }

    function test_onlyIssuerCanGrant() public {
        vm.expectRevert();
        vm.prank(STRANGER);
        checker.setPermission(STRANGER, PermissionFlags.ALL_ALLOWED);
    }

    /// @dev The baseline's defining limitation, asserted rather than merely stated in prose:
    ///      eligibility here never lapses. Time passing changes nothing, so revocation must always
    ///      be an explicit transaction per investor. `ENSAllowlistChecker`'s expiry tests are the
    ///      counterpart to this one.
    function test_eligibilityNeverExpiresOnItsOwn() public {
        vm.prank(ISSUER);
        checker.setPermission(ALICE, PermissionFlags.SWAP_ALLOWED);

        vm.warp(block.timestamp + 3650 days);

        _assertFlag(checker.checkAllowlist(ALICE, TOKEN), PermissionFlags.SWAP_ALLOWED);
    }
}
