// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {PermissionedRegistry} from "@ens/registry/PermissionedRegistry.sol";
import {IPermissionedRegistry} from "@ens/registry/interfaces/IPermissionedRegistry.sol";
import {IRegistry} from "@ens/registry/interfaces/IRegistry.sol";
import {RegistryRolesLib} from "@ens/registry/libraries/RegistryRolesLib.sol";
import {ILabelStore} from "@ens/utils/interfaces/ILabelStore.sol";
import {LibLabel} from "@ens/utils/LibLabel.sol";

import {PermissionFlag, PermissionFlags} from
    "v4-periphery/src/hooks/permissionedPools/libraries/PermissionFlags.sol";

import {MintAttestor} from "../src/cre/MintAttestor.sol";
import {IReceiver} from "../src/cre/IReceiver.sol";
import {ENSAllowlistChecker} from "../src/checker/ENSAllowlistChecker.sol";
import {CanopyRoles} from "../src/checker/CanopyRoles.sol";
import {StubLabelStore} from "./mocks/StubLabelStore.sol";

/// @notice Tests for the per-broker role ceiling (AND-mask) in MintAttestor.
contract RoleClampTest is Test {
    PermissionedRegistry internal platform;
    PermissionedRegistry internal acmeRegistry;
    PermissionedRegistry internal brokerA;
    PermissionedRegistry internal brokerB;

    MintAttestor internal attestor;
    ENSAllowlistChecker internal acmeChecker;

    address internal constant FORWARDER = address(0xF0FEED);
    address internal constant ACME_TOKEN = address(0xACE70);
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant OWNER = address(0xB055);
    address internal constant NON_OWNER = address(0xBAD);

    bytes32 internal constant WORKFLOW_ID = keccak256("canopy-eligibility-staging");
    uint64 internal constant EXPIRY = 2_000_000_000;

    uint256 internal constant SWAP = CanopyRoles.ROLE_ELIGIBLE_SWAP;
    uint256 internal constant LIQUIDITY = CanopyRoles.ROLE_ELIGIBLE_LIQUIDITY;
    uint256 internal constant BOTH = SWAP | LIQUIDITY;

    uint256 internal constant ROOT_ROLES = RegistryRolesLib.ROLE_REGISTRAR | RegistryRolesLib.ROLE_REGISTRAR_ADMIN
        | RegistryRolesLib.ROLE_SET_PARENT | RegistryRolesLib.ROLE_SET_SUBREGISTRY | RegistryRolesLib.ROLE_SET_RESOLVER
        | RegistryRolesLib.ROLE_RENEW;

    function setUp() public {
        vm.warp(1_000_000_000);

        StubLabelStore labelStore = new StubLabelStore();
        platform = new PermissionedRegistry(ILabelStore(address(labelStore)), address(this), ROOT_ROLES);
        acmeRegistry = new PermissionedRegistry(ILabelStore(address(labelStore)), address(this), ROOT_ROLES);
        brokerA = new PermissionedRegistry(ILabelStore(address(labelStore)), address(this), ROOT_ROLES);
        brokerB = new PermissionedRegistry(ILabelStore(address(labelStore)), address(this), ROOT_ROLES);

        _link(platform, acmeRegistry, "acme");
        _link(acmeRegistry, brokerA, "alpha");
        _link(acmeRegistry, brokerB, "beta");

        attestor = new MintAttestor(FORWARDER, IRegistry(address(platform)), address(this));

        acmeChecker = new ENSAllowlistChecker(
            IRegistry(address(platform)), IRegistry(address(acmeRegistry)), ACME_TOKEN, address(this)
        );
        acmeChecker.setAttestor(address(attestor));

        attestor.setChecker(address(acmeRegistry), acmeChecker);
        attestor.setAllowedWorkflowId(WORKFLOW_ID);

        brokerA.grantRootRoles(RegistryRolesLib.ROLE_REGISTRAR, address(attestor));
        brokerB.grantRootRoles(RegistryRolesLib.ROLE_REGISTRAR, address(attestor));
    }

    function _link(PermissionedRegistry parent, PermissionedRegistry child, string memory label) internal {
        parent.register(label, OWNER, IRegistry(address(child)), address(0), 0, EXPIRY);
        child.setParent(IRegistry(address(parent)), label);
    }

    function _label(string memory s) internal pure returns (bytes32 out) {
        bytes memory b = bytes(s);
        require(b.length <= 32, "label too long");
        assembly {
            out := mload(add(b, 32))
        }
    }

    function _metadata(bytes32 workflowId) internal pure returns (bytes memory) {
        return abi.encodePacked(workflowId, bytes32(0));
    }

    function _report(address subject, string memory label, address parentRegistry, uint256 roles, bool approved)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(uint8(0), subject, _label(label), parentRegistry, roles, EXPIRY, approved);
    }

    // ── Test 1: Clamp strips liquidity ──

    function test_clampStripsLiquidity() public {
        attestor.setCeiling(address(brokerA), SWAP);

        vm.recordLogs();
        vm.prank(FORWARDER);
        attestor.onReport(
            _metadata(WORKFLOW_ID), _report(ALICE, "alice", address(brokerA), BOTH, true)
        );

        // Registered with SWAP only
        IPermissionedRegistry.State memory state = brokerA.getState(LibLabel.id("alice"));
        assertEq(uint256(state.status), uint256(IPermissionedRegistry.Status.REGISTERED));

        assertEq(
            PermissionFlag.unwrap(acmeChecker.checkAllowlist(ALICE, ACME_TOKEN)),
            PermissionFlag.unwrap(PermissionFlags.SWAP_ALLOWED)
        );

        // RoleClamped event emitted
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool found;
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].topics[0] == MintAttestor.RoleClamped.selector) {
                (uint256 original, uint256 effective) = abi.decode(logs[i].data, (uint256, uint256));
                assertEq(original, BOTH);
                assertEq(effective, SWAP);
                found = true;
            }
        }
        assertTrue(found, "RoleClamped event expected");
    }

    // ── Test 2: No-op when within ceiling ──

    function test_noopWhenWithinCeiling() public {
        attestor.setCeiling(address(brokerA), BOTH);

        vm.recordLogs();
        vm.prank(FORWARDER);
        attestor.onReport(
            _metadata(WORKFLOW_ID), _report(ALICE, "alice", address(brokerA), SWAP, true)
        );

        assertEq(
            PermissionFlag.unwrap(acmeChecker.checkAllowlist(ALICE, ACME_TOKEN)),
            PermissionFlag.unwrap(PermissionFlags.SWAP_ALLOWED)
        );

        // No RoleClamped event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; i++) {
            assertTrue(logs[i].topics[0] != MintAttestor.RoleClamped.selector, "unexpected RoleClamped");
        }
    }

    // ── Test 3: type(uint256).max passes everything ──

    function test_maxCeilingPassesEverything() public {
        attestor.setCeiling(address(brokerA), type(uint256).max);

        vm.recordLogs();
        vm.prank(FORWARDER);
        attestor.onReport(
            _metadata(WORKFLOW_ID), _report(ALICE, "alice", address(brokerA), BOTH, true)
        );

        assertEq(
            PermissionFlag.unwrap(acmeChecker.checkAllowlist(ALICE, ACME_TOKEN)),
            PermissionFlag.unwrap(PermissionFlags.SWAP_ALLOWED | PermissionFlags.LIQUIDITY_ALLOWED)
        );

        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; i++) {
            assertTrue(logs[i].topics[0] != MintAttestor.RoleClamped.selector, "unexpected RoleClamped");
        }
    }

    // ── Test 4: Zero ceiling (not set) reverts ──

    function test_zeroCeilingReverts() public {
        // Do NOT set ceiling — it defaults to 0

        vm.expectRevert(abi.encodeWithSelector(MintAttestor.CeilingNotSet.selector, address(brokerA)));
        vm.prank(FORWARDER);
        attestor.onReport(
            _metadata(WORKFLOW_ID), _report(ALICE, "alice", address(brokerA), SWAP, true)
        );
    }

    // ── Test 5: Ceiling is per-broker ──

    function test_ceilingIsPerBroker() public {
        attestor.setCeiling(address(brokerA), SWAP);       // swap-only
        attestor.setCeiling(address(brokerB), BOTH);       // full access

        vm.prank(FORWARDER);
        attestor.onReport(
            _metadata(WORKFLOW_ID), _report(ALICE, "alice", address(brokerA), BOTH, true)
        );

        vm.prank(FORWARDER);
        attestor.onReport(
            _metadata(WORKFLOW_ID), _report(BOB, "bob", address(brokerB), BOTH, true)
        );

        // Alice (broker A, swap-only ceiling) → swap only
        assertEq(
            PermissionFlag.unwrap(acmeChecker.checkAllowlist(ALICE, ACME_TOKEN)),
            PermissionFlag.unwrap(PermissionFlags.SWAP_ALLOWED)
        );

        // Bob (broker B, full ceiling) → swap + liquidity
        assertEq(
            PermissionFlag.unwrap(acmeChecker.checkAllowlist(BOB, ACME_TOKEN)),
            PermissionFlag.unwrap(PermissionFlags.SWAP_ALLOWED | PermissionFlags.LIQUIDITY_ALLOWED)
        );
    }

    // ── Test 6: setCeiling(0) reverts ──

    function test_setCeilingZeroReverts() public {
        vm.expectRevert("zero ceiling would strip all roles; leave checker unwired instead");
        attestor.setCeiling(address(brokerA), 0);
    }

    // ── Test 7: Only owner can set ceiling ──

    function test_onlyOwnerCanSetCeiling() public {
        vm.expectRevert(abi.encodeWithSelector(MintAttestor.NotOwner.selector, NON_OWNER));
        vm.prank(NON_OWNER);
        attestor.setCeiling(address(brokerA), SWAP);
    }

    // ── Test 8: End-to-end with checker ──

    function test_clampedRolesWorkWithChecker() public {
        attestor.setCeiling(address(brokerA), SWAP);

        // Report grants BOTH, but ceiling clamps to SWAP
        vm.prank(FORWARDER);
        attestor.onReport(
            _metadata(WORKFLOW_ID), _report(ALICE, "alice", address(brokerA), BOTH, true)
        );

        // Checker correctly reflects clamped roles
        PermissionFlag flag = acmeChecker.checkAllowlist(ALICE, ACME_TOKEN);
        assertEq(PermissionFlag.unwrap(flag), PermissionFlag.unwrap(PermissionFlags.SWAP_ALLOWED));

        // Specifically NOT liquidity
        assertTrue(
            PermissionFlag.unwrap(flag) != PermissionFlag.unwrap(PermissionFlags.SWAP_ALLOWED | PermissionFlags.LIQUIDITY_ALLOWED),
            "liquidity should have been stripped"
        );
    }

    // ── Test 9: CeilingSet event ──

    function test_ceilingSetEvent() public {
        vm.recordLogs();
        attestor.setCeiling(address(brokerA), SWAP);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool found;
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].topics[0] == MintAttestor.CeilingSet.selector) {
                assertEq(address(uint160(uint256(logs[i].topics[1]))), address(brokerA));
                uint256 ceiling = abi.decode(logs[i].data, (uint256));
                assertEq(ceiling, SWAP);
                found = true;
            }
        }
        assertTrue(found, "CeilingSet event expected");
    }
}
