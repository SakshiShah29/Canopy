// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console2} from "forge-std/Test.sol";

import {PermissionFlag, PermissionFlags} from
    "v4-periphery/src/hooks/permissionedPools/libraries/PermissionFlags.sol";

import {PermissionedRegistry} from "@ens/registry/PermissionedRegistry.sol";
import {IPermissionedRegistry} from "@ens/registry/interfaces/IPermissionedRegistry.sol";
import {IRegistry} from "@ens/registry/interfaces/IRegistry.sol";
import {RegistryRolesLib} from "@ens/registry/libraries/RegistryRolesLib.sol";
import {ILabelStore} from "@ens/utils/interfaces/ILabelStore.sol";
import {LibLabel} from "@ens/utils/LibLabel.sol";

import {ENSAllowlistChecker} from "../../src/checker/ENSAllowlistChecker.sol";
import {CanopyRoles} from "../../src/checker/CanopyRoles.sol";
import {StubLabelStore} from "../mocks/StubLabelStore.sol";

/// @notice Gate 1 — what does a hierarchy walk actually cost?
///
/// @dev Measured against the **real** `PermissionedRegistry`, not a mock: storage layout and code
///      paths are the entire cost, so a mock would measure nothing useful.
///
///      Three checkers share one hierarchy and differ only in `ROOT_ANCHOR`, which is what sets
///      the walk depth. That isolates the marginal cost of a hop from the fixed cost of the leaf
///      read, which matters because the gate's failure criterion is *per hop*:
///
///        depth 1  anchor = brokerRegistry   leaf read only, walk terminates immediately
///        depth 2  anchor = issuerRegistry   + 1 ancestor
///        depth 3  anchor = ethRegistry      + 2 ancestors   <- the shipping hierarchy
///
///      Each measurement sits at the top of its own test body so the accessed accounts and slots
///      are cold, matching a real swap's first `isAllowed` call.
contract Gate1HierarchyGasTest is Test {
    uint256 internal constant PASS_BUDGET = 120_000;
    uint256 internal constant PER_HOP_LIMIT = 40_000;

    PermissionedRegistry internal ethRegistry;
    PermissionedRegistry internal issuerRegistry;
    PermissionedRegistry internal brokerRegistry;

    ENSAllowlistChecker internal checker1;
    ENSAllowlistChecker internal checker2;
    ENSAllowlistChecker internal checker3;

    address internal constant TOKEN = address(0xC0FFEE);
    address internal constant ALICE = address(0xA11CE);
    /// @dev Names are held by EOAs, as they are in production. The test contract stays the
    ///      *registrar* (it holds `ROLE_REGISTRAR`) without ever holding an ERC-1155 name token.
    address internal constant OWNER = address(0xB055);

    uint64 internal constant EXPIRY = 2_000_000_000;

    uint256 internal constant ROOT_ROLES = RegistryRolesLib.ROLE_REGISTRAR | RegistryRolesLib.ROLE_SET_PARENT
        | RegistryRolesLib.ROLE_SET_SUBREGISTRY | RegistryRolesLib.ROLE_SET_RESOLVER | RegistryRolesLib.ROLE_RENEW;

    function setUp() public {
        vm.warp(1_000_000_000);

        StubLabelStore labelStore = new StubLabelStore();

        ethRegistry = new PermissionedRegistry(ILabelStore(address(labelStore)), address(this), ROOT_ROLES);
        issuerRegistry = new PermissionedRegistry(ILabelStore(address(labelStore)), address(this), ROOT_ROLES);
        brokerRegistry = new PermissionedRegistry(ILabelStore(address(labelStore)), address(this), ROOT_ROLES);

        // canopy-demo.eth -> issuerRegistry
        ethRegistry.register("canopy-demo", OWNER, IRegistry(address(issuerRegistry)), address(0), 0, EXPIRY);
        issuerRegistry.setParent(IRegistry(address(ethRegistry)), "canopy-demo");

        // brokerA.canopy-demo.eth -> brokerRegistry
        issuerRegistry.register("brokerA", OWNER, IRegistry(address(brokerRegistry)), address(0), 0, EXPIRY);
        brokerRegistry.setParent(IRegistry(address(issuerRegistry)), "brokerA");

        // alice.brokerA.canopy-demo.eth, swap-eligible
        brokerRegistry.register(
            "alice", ALICE, IRegistry(address(0)), address(0), CanopyRoles.ROLE_ELIGIBLE_SWAP, EXPIRY
        );

        // `issuer` is the registry the walk must pass through. At depth 1 the walk terminates
        // immediately at the broker registry, so that is also the registry it passes through.
        checker1 = _deployChecker(IRegistry(address(brokerRegistry)), IRegistry(address(brokerRegistry)));
        checker2 = _deployChecker(IRegistry(address(issuerRegistry)), IRegistry(address(issuerRegistry)));
        checker3 = _deployChecker(IRegistry(address(ethRegistry)), IRegistry(address(issuerRegistry)));
    }

    function _deployChecker(IRegistry anchor, IRegistry issuer) internal returns (ENSAllowlistChecker c) {
        c = new ENSAllowlistChecker(anchor, issuer, TOKEN, address(this));
        c.setAttestor(address(this));
        c.recordPath(ALICE, IPermissionedRegistry(address(brokerRegistry)), LibLabel.id("alice"));
    }

    /// @dev Measures a cold call, then a warm one. A swap touches `isAllowed` twice — once from
    ///      `_pay` and once from `_take` — so the real cost added to a swap is cold + warm, not
    ///      two cold calls.
    function _measure(ENSAllowlistChecker c) internal view returns (uint256 cold, uint256 warm) {
        uint256 before = gasleft();
        PermissionFlag flag = c.checkAllowlist(ALICE, TOKEN);
        cold = before - gasleft();

        before = gasleft();
        c.checkAllowlist(ALICE, TOKEN);
        warm = before - gasleft();

        // A measurement of a denying path would be meaningless.
        require(PermissionFlag.unwrap(flag) == PermissionFlag.unwrap(PermissionFlags.SWAP_ALLOWED), "not eligible");
    }

    function test_gate1_depth1() public view {
        (uint256 cold, uint256 warm) = _measure(checker1);
        console2.log("depth 1  cold", cold);
        console2.log("depth 1  warm", warm);
    }

    function test_gate1_depth2() public view {
        (uint256 cold, uint256 warm) = _measure(checker2);
        console2.log("depth 2  cold", cold);
        console2.log("depth 2  warm", warm);
    }

    function test_gate1_depth3() public view {
        (uint256 cold, uint256 warm) = _measure(checker3);
        console2.log("depth 3  cold", cold);
        console2.log("depth 3  warm", warm);
    }

    /// @notice The gate itself: the shipping 3-hop walk, measured cold and first in its own
    ///         transaction so nothing is pre-warmed.
    /// @dev The per-hop slope is *not* computed here. Measuring several depths in one transaction
    ///      would warm the registries after the first call, making every later depth look cheaper
    ///      than it is. Take the slope by comparing the three `test_gate1_depth*` figures, each of
    ///      which runs in its own transaction against cold state.
    function test_gate1_verdict() public view {
        (uint256 cold, uint256 warm) = _measure(checker3);

        console2.log("--- Gate 1: 3-hop walk ---");
        console2.log("cold                       ", cold);
        console2.log("warm (2nd call in same tx) ", warm);
        console2.log("per-swap total (cold+warm) ", cold + warm);

        assertLt(cold, PASS_BUDGET, "Gate 1 FAILED: 3-hop walk over budget");
    }
}
