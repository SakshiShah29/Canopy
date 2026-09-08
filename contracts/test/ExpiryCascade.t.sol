// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPermissionedRegistry} from "@ens/registry/interfaces/IPermissionedRegistry.sol";
import {IRegistry} from "@ens/registry/interfaces/IRegistry.sol";
import {LibLabel} from "@ens/utils/LibLabel.sol";

import {PermissionFlags} from "v4-periphery/src/hooks/permissionedPools/libraries/PermissionFlags.sol";

import {MultiIssuerHierarchy} from "./fixtures/MultiIssuerHierarchy.sol";

/// @notice The claim the whole project rests on: revocation is a name expiring, not a transaction.
///
/// @dev `ENSAllowlistChecker.t.sol` already proves the cascade against a single issuer. What is
///      only provable with two is that the cascade **stops** — at the issuer boundary, and at the
///      broker boundary. A kill switch would produce identical output for beats 11 and 12; only
///      beat 13, the survivor, distinguishes "this broker's book lapsed" from "we turned it off".
///
///      Every test here drives time forward and sends no transaction against the investors.
contract ExpiryCascadeTest is MultiIssuerHierarchy {
    // ── the two tiers ────────────────────────────────────────────

    /// @dev Beats 4 and 8's precondition. Two successes prove nothing about a tier split unless
    ///      the tiers actually differ, so this is asserted before anything is expired.
    function test_tiersAreDistinctBeforeAnythingLapses() public view {
        _assertFlag(_acme(ALICE), PermissionFlags.SWAP_ALLOWED, "retail is swap-only");
        _assertFlag(
            _acme(MM),
            PermissionFlags.SWAP_ALLOWED | PermissionFlags.LIQUIDITY_ALLOWED,
            "the market maker holds both bits"
        );
    }

    // ── beat 11/12: the broker lapse ─────────────────────────────

    /// @dev The money shot. One name expires and two investors lose access in the same block,
    ///      with no transaction sent against either of them.
    function test_brokerLapseCutsOffEveryInvestorBeneathIt() public {
        vm.warp(T1);

        _assertFlag(_acme(ALICE), PermissionFlags.NONE, "retail cut off by the broker's lapse");
        _assertFlag(_acme(MM), PermissionFlags.NONE, "market maker cut off by the same lapse");
    }

    /// @dev And it really is the broker. Both investors' own names are still registered and
    ///      unexpired — nothing was revoked from them, the ground moved underneath.
    function test_lapsedBrokersInvestorNamesRemainValidThemselves() public {
        vm.warp(T1);

        string[2] memory labels = ["alice", "mm"];
        for (uint256 i = 0; i < labels.length; i++) {
            IPermissionedRegistry.State memory leaf = acmePrime.getState(LibLabel.id(labels[i]));
            assertEq(
                uint256(leaf.status), uint256(IPermissionedRegistry.Status.REGISTERED), "leaf still registered"
            );
            assertGt(leaf.expiry, block.timestamp, "leaf has not expired");
        }
    }

    // ── beat 13: containment ─────────────────────────────────────

    /// @dev The half that makes beat 11 mean anything. `prime` is one broker onboarded by two
    ///      issuers, so it is two names in two registries; Acme dropping theirs cannot reach into
    ///      Zenith's book. Without this assertion the demo is indistinguishable from a kill switch.
    function test_brokerLapseIsContainedToThatIssuer() public {
        vm.warp(T1);

        _assertFlag(_acme(ALICE), PermissionFlags.NONE, "acme/prime has lapsed");
        _assertFlag(_zenith(BOB), PermissionFlags.SWAP_ALLOWED, "the same broker under zenith is untouched");
        _assertFlag(
            _zenith(MM2),
            PermissionFlags.SWAP_ALLOWED | PermissionFlags.LIQUIDITY_ALLOWED,
            "and so is its market maker"
        );
    }

    /// @dev Contained sideways as well as across issuers: Acme's other broker is unaffected.
    function test_brokerLapseLeavesTheIssuersOtherBrokersAlone() public {
        vm.warp(T1);

        _assertFlag(_acme(ALICE), PermissionFlags.NONE, "acme/prime has lapsed");
        _assertFlag(_acme(CAROL), PermissionFlags.SWAP_ALLOWED, "acme/delta has not");
    }

    // ── the issuer lapse ─────────────────────────────────────────

    /// @dev One level up, and deliberately read through `delta` rather than `prime`. At T2 delta's
    ///      own name is still alive — it expires at 2.9e9 — so carol going dark can only be the
    ///      issuer above her. Read through `prime` instead and this test would pass for the wrong
    ///      reason, since prime lapsed at T1 regardless.
    function test_issuerLapseCascadesThroughABrokerThatIsStillAlive() public {
        vm.warp(T2);

        IPermissionedRegistry.State memory delta = acmeRegistry.getState(LibLabel.id("delta"));
        assertGt(delta.expiry, block.timestamp, "delta itself has not expired");

        _assertFlag(_acme(CAROL), PermissionFlags.NONE, "the issuer above delta has lapsed");
    }

    function test_issuerLapseLeavesTheOtherIssuerUntouched() public {
        vm.warp(T2);

        _assertFlag(_acme(ALICE), PermissionFlags.NONE, "acme is gone");
        _assertFlag(_acme(CAROL), PermissionFlags.NONE, "acme is gone for every broker beneath it");
        _assertFlag(_zenith(BOB), PermissionFlags.SWAP_ALLOWED, "zenith is a separate tree");
    }

    /// @dev An issuer can also be dropped outright rather than left to expire — the platform
    ///      unregistering them. Same cascade, immediately.
    function test_unregisteringAnIssuerCascadesImmediately() public {
        platform.unregister(LibLabel.id("acme"));

        _assertFlag(_acme(ALICE), PermissionFlags.NONE, "issuer unregistered");
        _assertFlag(_acme(CAROL), PermissionFlags.NONE, "and every broker beneath it");
        _assertFlag(_zenith(BOB), PermissionFlags.SWAP_ALLOWED, "the other issuer is unaffected");
    }

    // ── beat 15: re-registration ─────────────────────────────────

    /// @dev Reinstating a broker restores its book, and that is the issuer's decision to make:
    ///      only Acme holds `ROLE_REGISTRAR` on Acme's registry, so a lapsed broker cannot do this
    ///      to itself. The investors' names never expired; the ground came back.
    ///
    ///      Recorded because it is the boundary of the claim below, and because it is the
    ///      behaviour the demo will actually show if `prime` is re-registered on camera.
    function test_reinstatingABrokerRestoresItsBook() public {
        vm.warp(T1);
        _assertFlag(_acme(ALICE), PermissionFlags.NONE, "lapsed");

        acmeRegistry.register("prime", OWNER, IRegistry(address(acmePrime)), address(0), 0, FAR_FUTURE);

        _assertFlag(_acme(ALICE), PermissionFlags.SWAP_ALLOWED, "the issuer reinstated this broker");
    }

    /// @dev A lapsed name can be taken by someone else. When Acme re-registers `prime` and points
    ///      it at a *different* registry, the old broker's investors are still recorded against the
    ///      old registry — whose `getParent()` still answers `(acmeRegistry, "prime")`, because
    ///      nothing clears it and it has no way to know it was orphaned.
    ///
    ///      This failed until the walk began confirming each link downward with `getSubregistry`:
    ///      checking only that the claimed label was *alive* let the incoming broker inherit the
    ///      whole of the outgoing one's book.
    function test_aDifferentBrokerTakingTheNameMustNotInheritTheBook() public {
        vm.warp(T1);
        _assertFlag(_acme(ALICE), PermissionFlags.NONE, "lapsed");

        // A new operator takes the freed name, with their own registry.
        acmeRegistry.register("prime", STRANGER, IRegistry(address(acmeDelta)), address(0), 0, FAR_FUTURE);

        _assertFlag(_acme(ALICE), PermissionFlags.NONE, "alice belongs to the broker that lost the name");
        _assertFlag(_acme(MM), PermissionFlags.NONE, "and so does the market maker");
    }
}
