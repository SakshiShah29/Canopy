// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {PermissionFlag, PermissionFlags} from
    "v4-periphery/src/hooks/permissionedPools/libraries/PermissionFlags.sol";
import {IAllowlistChecker} from "v4-periphery/src/hooks/permissionedPools/interfaces/IAllowlistChecker.sol";

import {IRegistry} from "@ens/registry/interfaces/IRegistry.sol";
import {IPermissionedRegistry} from "@ens/registry/interfaces/IPermissionedRegistry.sol";
import {LibLabel} from "@ens/utils/LibLabel.sol";

import {ENSAllowlistChecker} from "../src/checker/ENSAllowlistChecker.sol";
import {CanopyRoles} from "../src/checker/CanopyRoles.sol";
import {MockRegistry, RevertingRegistry} from "./mocks/MockRegistry.sol";

/// @notice Unit tests for the hierarchy walk, against mocked registries.
///
/// @dev The hierarchy under test mirrors the demo exactly:
///
///          ethRegistry           (ROOT_ANCHOR — the `.eth` registry, never expires)
///            └── "canopy-demo"   → issuerRegistry
///                  └── "brokerA" → brokerARegistry
///                        ├── "alice"  swap only
///                        └── "mm"     swap + liquidity
///
///      Live-chain behaviour is Day 3's job; everything here is deterministic.
contract ENSAllowlistCheckerTest is Test {
    ENSAllowlistChecker internal checker;

    MockRegistry internal ethRegistry;
    MockRegistry internal issuerRegistry;
    MockRegistry internal brokerARegistry;

    address internal constant TOKEN = address(0xC0FFEE);
    address internal constant OWNER = address(0xB055);
    address internal constant ATTESTOR = address(0xA77E57);

    address internal constant ALICE = address(0xA11CE);
    address internal constant MM = address(0xFEED);
    address internal constant STRANGER = address(0x5747A);

    uint64 internal constant FAR_FUTURE = 4_000_000_000;
    uint64 internal constant BROKER_EXPIRY = 2_000_000_000;
    uint64 internal constant LEAF_EXPIRY = 3_000_000_000;

    function setUp() public {
        // Start well before every expiry used below.
        vm.warp(1_000_000_000);

        ethRegistry = new MockRegistry();
        issuerRegistry = new MockRegistry();
        brokerARegistry = new MockRegistry();

        checker = new ENSAllowlistChecker(IRegistry(address(ethRegistry)), TOKEN, OWNER);
        vm.prank(OWNER);
        checker.setAttestor(ATTESTOR);

        // `.eth` level
        ethRegistry.register("canopy-demo", OWNER, FAR_FUTURE);
        issuerRegistry.setParent(IRegistry(address(ethRegistry)), "canopy-demo");

        // issuer level
        issuerRegistry.register("brokerA", OWNER, BROKER_EXPIRY);
        brokerARegistry.setParent(IRegistry(address(issuerRegistry)), "brokerA");

        // broker level
        _registerInvestor("alice", ALICE, CanopyRoles.ROLE_ELIGIBLE_SWAP);
        _registerInvestor("mm", MM, CanopyRoles.ROLE_ELIGIBLE_SWAP | CanopyRoles.ROLE_ELIGIBLE_LIQUIDITY);
    }

    function _registerInvestor(string memory label, address who, uint256 roleBitmap) internal {
        brokerARegistry.register(label, who, LEAF_EXPIRY);
        brokerARegistry.grantRoles(brokerARegistry.resourceOf(label), roleBitmap, who);
        vm.prank(ATTESTOR);
        checker.recordPath(who, IPermissionedRegistry(address(brokerARegistry)), LibLabel.id(label));
    }

    function _check(address who) internal view returns (PermissionFlag) {
        return checker.checkAllowlist(who, TOKEN);
    }

    function _assertFlag(PermissionFlag actual, PermissionFlag expected) internal pure {
        assertEq(PermissionFlag.unwrap(actual), PermissionFlag.unwrap(expected));
    }

    // -------------------------------------------------------------------------
    // Happy paths
    // -------------------------------------------------------------------------

    function test_swapOnlyInvestor() public view {
        _assertFlag(_check(ALICE), PermissionFlags.SWAP_ALLOWED);
    }

    function test_marketMakerGetsBothFlags() public view {
        _assertFlag(_check(MM), PermissionFlags.SWAP_ALLOWED | PermissionFlags.LIQUIDITY_ALLOWED);
    }

    /// @dev The tier split as the adapter sees it: `isAllowed` tests containment, so a swap-only
    ///      investor must fail the liquidity gate while passing the swap gate.
    function test_tierSplitAsAdapterEvaluatesIt() public view {
        PermissionFlag alice = _check(ALICE);
        assertTrue((alice & PermissionFlags.SWAP_ALLOWED) == PermissionFlags.SWAP_ALLOWED);
        assertFalse((alice & PermissionFlags.LIQUIDITY_ALLOWED) == PermissionFlags.LIQUIDITY_ALLOWED);

        PermissionFlag mm = _check(MM);
        assertTrue((mm & PermissionFlags.SWAP_ALLOWED) == PermissionFlags.SWAP_ALLOWED);
        assertTrue((mm & PermissionFlags.LIQUIDITY_ALLOWED) == PermissionFlags.LIQUIDITY_ALLOWED);
    }

    function test_unknownAccountGetsNothing() public view {
        _assertFlag(_check(STRANGER), PermissionFlags.NONE);
    }

    // -------------------------------------------------------------------------
    // Expiry — the cascade
    // -------------------------------------------------------------------------

    function test_expiredLeafRevokesOnlyThatInvestor() public {
        vm.warp(LEAF_EXPIRY);
        _assertFlag(_check(ALICE), PermissionFlags.NONE);
        _assertFlag(_check(MM), PermissionFlags.NONE);
    }

    /// @dev The money shot. `brokerA` lapses; both investors beneath it lose access in the same
    ///      block, with no transaction sent against either of them and their own names untouched.
    function test_expiredBrokerCascadesToEveryInvestorBeneathIt() public {
        _assertFlag(_check(ALICE), PermissionFlags.SWAP_ALLOWED);
        _assertFlag(_check(MM), PermissionFlags.SWAP_ALLOWED | PermissionFlags.LIQUIDITY_ALLOWED);

        vm.warp(BROKER_EXPIRY);

        _assertFlag(_check(ALICE), PermissionFlags.NONE);
        _assertFlag(_check(MM), PermissionFlags.NONE);

        // The investors' own names are still perfectly valid — only the broker lapsed.
        IPermissionedRegistry.State memory aliceState =
            IPermissionedRegistry(address(brokerARegistry)).getState(LibLabel.id("alice"));
        assertEq(uint256(aliceState.status), uint256(IPermissionedRegistry.Status.REGISTERED));
        assertGt(aliceState.expiry, block.timestamp);
    }

    /// @dev Expiry is exclusive upstream (`block.timestamp >= expiry` is expired), so the last
    ///      good second is `expiry - 1`. Worth pinning: an off-by-one here would have the demo
    ///      lapse a second early or late on camera.
    function test_expiryBoundaryIsExclusive() public {
        vm.warp(BROKER_EXPIRY - 1);
        _assertFlag(_check(ALICE), PermissionFlags.SWAP_ALLOWED);

        vm.warp(BROKER_EXPIRY);
        _assertFlag(_check(ALICE), PermissionFlags.NONE);
    }

    function test_expiredGrandparentCascades() public {
        ethRegistry.expire("canopy-demo");
        _assertFlag(_check(ALICE), PermissionFlags.NONE);
        _assertFlag(_check(MM), PermissionFlags.NONE);
    }

    function test_unregisteredAncestorDenies() public {
        issuerRegistry.unregister("brokerA");
        _assertFlag(_check(ALICE), PermissionFlags.NONE);
    }

    /// @dev A lapsed broker must not be able to resurrect its book by re-registering: the new
    ///      name gets a fresh EAC resource, so the old grants are orphaned rather than restored.
    function test_reRegistrationDoesNotResurrectOldGrants() public {
        vm.warp(BROKER_EXPIRY);
        _assertFlag(_check(ALICE), PermissionFlags.NONE);

        issuerRegistry.reRegister("brokerA", OWNER, FAR_FUTURE, 1);

        // The broker name is alive again, so the walk succeeds — but alice's leaf grant lives on
        // the old resource and confers nothing until she is re-attested.
        brokerARegistry.reRegister("alice", ALICE, FAR_FUTURE, 1);
        _assertFlag(_check(ALICE), PermissionFlags.NONE);
    }

    // -------------------------------------------------------------------------
    // Roles
    // -------------------------------------------------------------------------

    function test_revokingRoleRemovesOnlyThatFlag() public {
        brokerARegistry.revokeRoles(brokerARegistry.resourceOf("mm"), CanopyRoles.ROLE_ELIGIBLE_LIQUIDITY, MM);
        _assertFlag(_check(MM), PermissionFlags.SWAP_ALLOWED);
    }

    function test_investorWithNoRolesGetsNothing() public {
        brokerARegistry.register("bob", STRANGER, LEAF_EXPIRY);
        vm.prank(ATTESTOR);
        checker.recordPath(STRANGER, IPermissionedRegistry(address(brokerARegistry)), LibLabel.id("bob"));

        _assertFlag(_check(STRANGER), PermissionFlags.NONE);
    }

    /// @dev Grants must be keyed to the investor's own resource. A grant against a *different*
    ///      name's resource must not carry over — this is what makes per-subname granting sound.
    function test_grantOnAnotherNamesResourceDoesNotApply() public {
        brokerARegistry.register("carol", STRANGER, LEAF_EXPIRY);
        brokerARegistry.grantRoles(brokerARegistry.resourceOf("alice"), CanopyRoles.ROLE_ELIGIBLE_SWAP, STRANGER);
        vm.prank(ATTESTOR);
        checker.recordPath(STRANGER, IPermissionedRegistry(address(brokerARegistry)), LibLabel.id("carol"));

        _assertFlag(_check(STRANGER), PermissionFlags.NONE);
    }

    // -------------------------------------------------------------------------
    // The fail-closed walk
    // -------------------------------------------------------------------------

    /// @dev The trap this contract is built around. ENSv2's `setParent` is a separate call from
    ///      the parent's `setSubregistry`, so a registry can be wired downward but not upward. If
    ///      a null parent were read as "reached the top", every ancestor check would be skipped
    ///      and a lapsed broker's investors would keep trading forever.
    function test_registryWiredDownwardButNotUpwardDenies() public {
        brokerARegistry.clearParent();
        _assertFlag(_check(ALICE), PermissionFlags.NONE);
    }

    /// @dev A walk that never reaches `ROOT_ANCHOR` denies even when every name on it is alive.
    function test_walkNotReachingRootAnchorDenies() public {
        MockRegistry impostorRoot = new MockRegistry();
        impostorRoot.register("canopy-demo", OWNER, FAR_FUTURE);
        issuerRegistry.setParent(IRegistry(address(impostorRoot)), "canopy-demo");

        _assertFlag(_check(ALICE), PermissionFlags.NONE);
    }

    /// @dev A parent cycle must hit the hop bound and deny rather than run out of gas.
    function test_cyclicHierarchyTerminatesAndDenies() public {
        brokerARegistry.setParent(IRegistry(address(issuerRegistry)), "brokerA");
        issuerRegistry.setParent(IRegistry(address(brokerARegistry)), "loop");
        brokerARegistry.register("loop", OWNER, FAR_FUTURE);

        _assertFlag(_check(ALICE), PermissionFlags.NONE);
    }

    /// @dev A hostile address in the hierarchy may deny or revert, but must never grant.
    function test_hostileAncestorNeverGrants() public {
        RevertingRegistry hostile = new RevertingRegistry();
        brokerARegistry.setParent(IRegistry(address(hostile)), "brokerA");

        try checker.checkAllowlist(ALICE, TOKEN) returns (PermissionFlag flag) {
            _assertFlag(flag, PermissionFlags.NONE);
        } catch {
            // Reverting is an acceptable outcome; granting is not.
        }
    }

    // -------------------------------------------------------------------------
    // Token binding and access control
    // -------------------------------------------------------------------------

    function test_deniesForAnUnrelatedToken() public view {
        _assertFlag(checker.checkAllowlist(ALICE, address(0xBEEF)), PermissionFlags.NONE);
    }

    function test_onlyAttestorCanRecordPaths() public {
        vm.expectRevert(abi.encodeWithSelector(ENSAllowlistChecker.NotAttestor.selector, STRANGER));
        vm.prank(STRANGER);
        checker.recordPath(STRANGER, IPermissionedRegistry(address(brokerARegistry)), LibLabel.id("alice"));
    }

    function test_onlyOwnerCanSetAttestor() public {
        vm.expectRevert();
        vm.prank(STRANGER);
        checker.setAttestor(STRANGER);
    }

    /// @dev `PermissionsAdapter._updateAllowListChecker` rejects any checker that fails this, so
    ///      it gates whether our contract is installable at all.
    function test_advertisesAllowlistCheckerInterface() public view {
        assertTrue(checker.supportsInterface(type(IAllowlistChecker).interfaceId));
    }
}
