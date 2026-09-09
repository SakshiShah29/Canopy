// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PermissionedRegistry} from "@ens/registry/PermissionedRegistry.sol";
import {IPermissionedRegistry} from "@ens/registry/interfaces/IPermissionedRegistry.sol";
import {IRegistry} from "@ens/registry/interfaces/IRegistry.sol";
import {ILabelStore} from "@ens/utils/interfaces/ILabelStore.sol";
import {LibLabel} from "@ens/utils/LibLabel.sol";

import {PermissionFlag, PermissionFlags} from
    "v4-periphery/src/hooks/permissionedPools/libraries/PermissionFlags.sol";

import {ENSAllowlistChecker} from "../src/checker/ENSAllowlistChecker.sol";
import {CanopyRoles} from "../src/checker/CanopyRoles.sol";
import {StubLabelStore} from "./mocks/StubLabelStore.sol";
import {MultiIssuerHierarchy} from "./fixtures/MultiIssuerHierarchy.sol";

/// @notice Paths that must never grant.
///
/// @dev These are the failures that fail *open*. An expiry bug denies someone who should have
///      access — loud, and caught the first time anyone tries. An isolation bug grants someone who
///      should not, stays silent, and every happy path in the suite keeps passing. So each guard
///      gets a test whose only job is to watch it.
///
///      `ENSAllowlistChecker.t.sol` covers the single-issuer versions against mocks: a hostile
///      ancestor, a walk that never reaches the root anchor, a cycle, a registry wired downward but
///      not upward. What needs two real issuers is the guard added with the multi-issuer model —
///      that the walk must pass *through* `ISSUER_REGISTRY`, not merely arrive above it.
contract AdversarialPathTest is MultiIssuerHierarchy {
    /// @dev **The one that fails open.** Bob's name under Zenith is entirely legitimate — real
    ///      registry, real roles, unexpired, and its walk reaches the platform root exactly like
    ///      Acme's investors do. The only thing separating him from Acme's pool is that the walk
    ///      never passes through Acme's registry.
    ///
    ///      Recording him into Acme's checker is what a compromised workflow, or simply a wrong
    ///      `setChecker`, would produce. Delete the `throughIssuer` condition and this is the sole
    ///      test in the suite that notices: every other assertion still passes, because reaching
    ///      the shared root is a condition Bob genuinely satisfies.
    function test_leafFromAnotherIssuerRecordedIntoThisCheckerIsRefused() public {
        vm.prank(ATTESTOR);
        acmeChecker.recordPath(BOB, IPermissionedRegistry(address(zenithPrime)), LibLabel.id("bob"));

        _assertFlag(_acme(BOB), PermissionFlags.NONE, "a zenith name confers nothing in acme's pool");

        // And the name it came from is beyond reproach — this is a refusal, not a broken fixture.
        _assertFlag(_zenith(BOB), PermissionFlags.SWAP_ALLOWED, "still perfectly valid under zenith");
    }

    /// @dev The same guard from the other side: a broker hung directly off the platform, skipping
    ///      the issuer layer entirely. The walk terminates at `ROOT_ANCHOR` in one hop and every
    ///      name on it is alive, so arrival alone would grant.
    function test_brokerHungDirectlyOffThePlatformIsRefused() public {
        StubLabelStore labelStore = new StubLabelStore();
        PermissionedRegistry rogue =
            new PermissionedRegistry(ILabelStore(address(labelStore)), address(this), ROOT_ROLES);

        _link(platform, rogue, "rogue", FAR_FUTURE);
        rogue.register("eve", STRANGER, IRegistry(address(0)), address(0), CanopyRoles.ROLE_ELIGIBLE_SWAP, LEAF_EXPIRY);

        vm.prank(ATTESTOR);
        acmeChecker.recordPath(STRANGER, IPermissionedRegistry(address(rogue)), LibLabel.id("eve"));

        _assertFlag(_acme(STRANGER), PermissionFlags.NONE, "under the platform, but not under acme");
    }

    /// @dev A leaf directly under the issuer, with no broker in between, is legitimate — it is the
    ///      `throughIssuer` start condition. Included so the guard above is not mistaken for
    ///      "anything but the exact broker depth is refused".
    function test_leafDirectlyUnderTheIssuerIsAllowed() public {
        acmeRegistry.register(
            "house", STRANGER, IRegistry(address(0)), address(0), CanopyRoles.ROLE_ELIGIBLE_SWAP, LEAF_EXPIRY
        );

        vm.prank(ATTESTOR);
        acmeChecker.recordPath(STRANGER, IPermissionedRegistry(address(acmeRegistry)), LibLabel.id("house"));

        _assertFlag(_acme(STRANGER), PermissionFlags.SWAP_ALLOWED, "the issuer may onboard directly");
    }

    /// @dev A registry that simply *claims* a legitimate parent. `setParent` is permissioned by
    ///      the child's own roles, so anyone who deploys a registry holds them on it and can point
    ///      it at any name they like. Nothing on Acme's side consented to this.
    function test_registryClaimingALegitimateParentIsRefused() public {
        StubLabelStore labelStore = new StubLabelStore();
        PermissionedRegistry impostor =
            new PermissionedRegistry(ILabelStore(address(labelStore)), address(this), ROOT_ROLES);

        // The real acme/prime is alive and untouched; the impostor merely asserts it is that name.
        impostor.setParent(IRegistry(address(acmeRegistry)), "prime");
        impostor.register(
            "eve", STRANGER, IRegistry(address(0)), address(0), CanopyRoles.ROLE_ELIGIBLE_SWAP, LEAF_EXPIRY
        );

        vm.prank(ATTESTOR);
        acmeChecker.recordPath(STRANGER, IPermissionedRegistry(address(impostor)), LibLabel.id("eve"));

        _assertFlag(_acme(STRANGER), PermissionFlags.NONE, "acme never delegated `prime` to this registry");
    }

    // ── the recording boundary ───────────────────────────────────

    function test_recordPathFromANonAttestorReverts() public {
        vm.expectRevert(abi.encodeWithSelector(ENSAllowlistChecker.NotAttestor.selector, STRANGER));
        vm.prank(STRANGER);
        acmeChecker.recordPath(STRANGER, IPermissionedRegistry(address(acmePrime)), LibLabel.id("alice"));
    }

    /// @dev Recording is the only write, so the attestor is the only thing that has to be trusted —
    ///      and even it cannot mint eligibility out of nothing. A path to a label that was never
    ///      registered confers nothing.
    function test_attestorCannotRecordANameThatDoesNotExist() public {
        vm.prank(ATTESTOR);
        acmeChecker.recordPath(STRANGER, IPermissionedRegistry(address(acmePrime)), LibLabel.id("ghost"));

        _assertFlag(_acme(STRANGER), PermissionFlags.NONE, "no such name");
    }

    /// @dev A registry that is not a registry. The walk either reverts on the decode or denies;
    ///      what it must never do is grant. Asserting "denies or reverts" rather than one or the
    ///      other keeps this from pinning down behaviour that upstream is free to change.
    function test_leafOnANonRegistryAddressNeverGrants() public {
        vm.prank(ATTESTOR);
        acmeChecker.recordPath(STRANGER, IPermissionedRegistry(STRANGER), LibLabel.id("alice"));

        try acmeChecker.checkAllowlist(STRANGER, ACME_TOKEN) returns (PermissionFlag flag) {
            _assertFlag(flag, PermissionFlags.NONE, "a non-registry must not grant");
        } catch {
            // Reverting is equally acceptable: the caller gets no permission either way.
        }
    }

    // ── token scoping ────────────────────────────────────────────

    /// @dev Each checker answers for exactly one pool's token. Acme's investor asking about
    ///      Zenith's token is the cross-issuer swap of beat 9, seen at the checker level.
    function test_eligibilityDoesNotCarryToAnotherIssuersToken() public view {
        _assertFlag(_acme(ALICE), PermissionFlags.SWAP_ALLOWED, "alice is eligible in acme's pool");
        _assertFlag(
            acmeChecker.checkAllowlist(ALICE, ZENITH_TOKEN),
            PermissionFlags.NONE,
            "and holds nothing against zenith's token"
        );
        _assertFlag(_zenith(ALICE), PermissionFlags.NONE, "nor against zenith's checker");
    }
}
