// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {PermissionedRegistry} from "@ens/registry/PermissionedRegistry.sol";
import {IPermissionedRegistry} from "@ens/registry/interfaces/IPermissionedRegistry.sol";
import {IRegistry} from "@ens/registry/interfaces/IRegistry.sol";
import {RegistryRolesLib} from "@ens/registry/libraries/RegistryRolesLib.sol";
import {ILabelStore} from "@ens/utils/interfaces/ILabelStore.sol";
import {LibLabel} from "@ens/utils/LibLabel.sol";

import {PermissionFlag, PermissionFlags} from
    "v4-periphery/src/hooks/permissionedPools/libraries/PermissionFlags.sol";

import {ENSAllowlistChecker} from "../../src/checker/ENSAllowlistChecker.sol";
import {CanopyRoles} from "../../src/checker/CanopyRoles.sol";
import {StubLabelStore} from "../mocks/StubLabelStore.sol";

/// @notice The four-level, two-issuer tree the demo actually runs on, against real registries.
///
/// @dev `ENSAllowlistChecker.t.sol` predates the multi-issuer model: it walks a single issuer
///      against `MockRegistry`, which is right for the walk's own edge cases but cannot express
///      the two properties the model turns on — that one issuer's lapse leaves the other alone,
///      and that one issuer's checker refuses the other's investors. Those need two issuers, two
///      checkers, and real `getParent`/`getState`/`hasRoles` behaviour.
///
///        platform                                   (ROOT_ANCHOR — the walk terminates here)
///        ├── acme    exp 2.0e9
///        │    ├── prime  exp 1.5e9  ── alice (swap), mm (swap+liquidity)
///        │    └── delta  exp 2.9e9  ── carol (swap)
///        └── zenith  exp 3.0e9
///             └── prime  exp 2.6e9  ── bob (swap), mm2 (swap+liquidity)
///
///      The expiries are staggered so each cascade can be reached by `warp` alone, and so that
///      each one is *isolated* from the others:
///
///        T0 = 1.0e9  everything alive
///        T1 = 1.6e9  acme/prime has lapsed; acme itself has not, and delta has not
///        T2 = 2.1e9  acme has lapsed; **delta is still alive by its own expiry**
///
///      T2 is the reason `delta` exists. If the only broker under Acme were `prime`, an issuer
///      cascade test would be indistinguishable from the broker cascade that already happened at
///      T1 — carol going dark at T2 can only be the issuer above her, because her own broker is
///      still perfectly valid. Every leaf expires at 2.8e9, after both, so a dark investor is
///      never explained by their own name lapsing.
///
///      `prime` appears under both issuers on purpose: the same broker, onboarded twice, is two
///      names in two registries with two independent books.
abstract contract MultiIssuerHierarchy is Test {
    PermissionedRegistry internal platform;
    PermissionedRegistry internal acmeRegistry;
    PermissionedRegistry internal zenithRegistry;
    PermissionedRegistry internal acmePrime;
    PermissionedRegistry internal acmeDelta;
    PermissionedRegistry internal zenithPrime;

    ENSAllowlistChecker internal acmeChecker;
    ENSAllowlistChecker internal zenithChecker;

    address internal constant ACME_TOKEN = address(0xACE70);
    address internal constant ZENITH_TOKEN = address(0x2E417);

    address internal constant ALICE = address(0xA11CE);
    address internal constant MM = address(0xFEED);
    address internal constant CAROL = address(0xCA401);
    address internal constant BOB = address(0xB0B);
    address internal constant MM2 = address(0xFEED2);

    address internal constant OWNER = address(0xB055);
    address internal constant ATTESTOR = address(0xA77E57);
    address internal constant STRANGER = address(0x5747A);

    uint64 internal constant T0 = 1_000_000_000;
    uint64 internal constant ACME_PRIME_EXPIRY = 1_500_000_000;
    uint64 internal constant T1 = 1_600_000_000;
    uint64 internal constant ACME_EXPIRY = 2_000_000_000;
    uint64 internal constant T2 = 2_100_000_000;
    uint64 internal constant ZENITH_PRIME_EXPIRY = 2_600_000_000;
    uint64 internal constant LEAF_EXPIRY = 2_800_000_000;
    uint64 internal constant ACME_DELTA_EXPIRY = 2_900_000_000;
    uint64 internal constant ZENITH_EXPIRY = 3_000_000_000;
    uint64 internal constant FAR_FUTURE = 4_000_000_000;

    /// @dev `ROLE_REGISTRAR_ADMIN` is not decoration: `grantRootRoles` requires the `_ADMIN` twin
    ///      of the role being granted (risk #10). Without it the fixture cannot register at all.
    uint256 internal constant ROOT_ROLES = RegistryRolesLib.ROLE_REGISTRAR | RegistryRolesLib.ROLE_REGISTRAR_ADMIN
        | RegistryRolesLib.ROLE_SET_PARENT | RegistryRolesLib.ROLE_SET_SUBREGISTRY | RegistryRolesLib.ROLE_SET_RESOLVER
        | RegistryRolesLib.ROLE_RENEW | RegistryRolesLib.ROLE_UNREGISTER | RegistryRolesLib.ROLE_UNREGISTER_ADMIN;

    function setUp() public virtual {
        vm.warp(T0);

        StubLabelStore labelStore = new StubLabelStore();
        platform = _registry(labelStore);
        acmeRegistry = _registry(labelStore);
        zenithRegistry = _registry(labelStore);
        acmePrime = _registry(labelStore);
        acmeDelta = _registry(labelStore);
        zenithPrime = _registry(labelStore);

        _link(platform, acmeRegistry, "acme", ACME_EXPIRY);
        _link(platform, zenithRegistry, "zenith", ZENITH_EXPIRY);
        _link(acmeRegistry, acmePrime, "prime", ACME_PRIME_EXPIRY);
        _link(acmeRegistry, acmeDelta, "delta", ACME_DELTA_EXPIRY);
        _link(zenithRegistry, zenithPrime, "prime", ZENITH_PRIME_EXPIRY);

        // The walk terminates at the platform, so each checker is anchored there but must also
        // pass *through* its own issuer. That second condition is the isolation guard.
        acmeChecker = new ENSAllowlistChecker(
            IRegistry(address(platform)), IRegistry(address(acmeRegistry)), ACME_TOKEN, OWNER
        );
        zenithChecker = new ENSAllowlistChecker(
            IRegistry(address(platform)), IRegistry(address(zenithRegistry)), ZENITH_TOKEN, OWNER
        );
        vm.startPrank(OWNER);
        acmeChecker.setAttestor(ATTESTOR);
        zenithChecker.setAttestor(ATTESTOR);
        vm.stopPrank();

        _onboard(acmeChecker, acmePrime, "alice", ALICE, CanopyRoles.ROLE_ELIGIBLE_SWAP);
        _onboard(
            acmeChecker,
            acmePrime,
            "mm",
            MM,
            CanopyRoles.ROLE_ELIGIBLE_SWAP | CanopyRoles.ROLE_ELIGIBLE_LIQUIDITY
        );
        _onboard(acmeChecker, acmeDelta, "carol", CAROL, CanopyRoles.ROLE_ELIGIBLE_SWAP);
        _onboard(zenithChecker, zenithPrime, "bob", BOB, CanopyRoles.ROLE_ELIGIBLE_SWAP);
        _onboard(
            zenithChecker,
            zenithPrime,
            "mm2",
            MM2,
            CanopyRoles.ROLE_ELIGIBLE_SWAP | CanopyRoles.ROLE_ELIGIBLE_LIQUIDITY
        );
    }

    function _registry(StubLabelStore labelStore) private returns (PermissionedRegistry) {
        return new PermissionedRegistry(ILabelStore(address(labelStore)), address(this), ROOT_ROLES);
    }

    /// @dev Both directions. `setSubregistry` alone leaves the child reporting no parent at all,
    ///      which is exactly where the upward walk would stop.
    function _link(PermissionedRegistry parent, PermissionedRegistry child, string memory label, uint64 expiry)
        internal
    {
        parent.register(label, OWNER, IRegistry(address(child)), address(0), 0, expiry);
        child.setParent(IRegistry(address(parent)), label);
    }

    /// @dev What `MintAttestor.onReport` does on an APPROVE: register the subname with its role
    ///      bits, then record the leaf in that issuer's own checker.
    function _onboard(
        ENSAllowlistChecker checker,
        PermissionedRegistry broker,
        string memory label,
        address who,
        uint256 roles
    ) internal {
        broker.register(label, who, IRegistry(address(0)), address(0), roles, LEAF_EXPIRY);
        vm.prank(ATTESTOR);
        checker.recordPath(who, IPermissionedRegistry(address(broker)), LibLabel.id(label));
    }

    // ── assertions ───────────────────────────────────────────────

    function _acme(address who) internal view returns (PermissionFlag) {
        return acmeChecker.checkAllowlist(who, ACME_TOKEN);
    }

    function _zenith(address who) internal view returns (PermissionFlag) {
        return zenithChecker.checkAllowlist(who, ZENITH_TOKEN);
    }

    function _assertFlag(PermissionFlag actual, PermissionFlag expected, string memory reason) internal pure {
        assertEq(PermissionFlag.unwrap(actual), PermissionFlag.unwrap(expected), reason);
    }
}
