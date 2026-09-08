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

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {ApplicationContract} from "../../src/cre/ApplicationContract.sol";
import {MintAttestor} from "../../src/cre/MintAttestor.sol";
import {IReceiver} from "../../src/cre/IReceiver.sol";
import {LibCanopyPath} from "../../src/cre/LibCanopyPath.sol";
import {ENSAllowlistChecker} from "../../src/checker/ENSAllowlistChecker.sol";
import {CanopyRoles} from "../../src/checker/CanopyRoles.sol";
import {StubLabelStore} from "../mocks/StubLabelStore.sol";

/// @notice The two contracts that bracket the CRE boundary, against real registries.
///
/// @dev A four-level tree with one broker onboarded by both issuers, which is the shape the whole
///      multi-issuer model turns on:
///
///        platform
///        ├── acme    ── prime ── (investors)
///        └── zenith  ── prime ── (investors)
///
///      Two things here are load-bearing rather than incidental:
///
///      - `brokerPath` is **derived** from the broker's registry, so an applicant cannot pick the
///        loosest entry in the confidential rulebook and be evaluated under it.
///      - The checker a mint records into is **derived** from the same walk, so a workflow that
///        produced a bad report still cannot direct eligibility into an unrelated issuer's pool.
///
///      Both use real `PermissionedRegistry` instances: the walk reads `getParent()` and
///      `getState()`, and a mock would be asserting against our own assumptions.
contract CREBoundaryTest is Test {
    PermissionedRegistry internal platform;
    PermissionedRegistry internal acmeRegistry;
    PermissionedRegistry internal zenithRegistry;
    PermissionedRegistry internal acmePrime;
    PermissionedRegistry internal zenithPrime;

    ApplicationContract internal app;
    MintAttestor internal attestor;
    ENSAllowlistChecker internal acmeChecker;
    ENSAllowlistChecker internal zenithChecker;

    address internal constant FORWARDER = address(0xF0FEED);
    address internal constant ACME_TOKEN = address(0xACE70);
    address internal constant ZENITH_TOKEN = address(0x2E417);
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant OWNER = address(0xB055);

    bytes32 internal constant WORKFLOW_ID = keccak256("canopy-eligibility-staging");
    uint64 internal constant EXPIRY = 2_000_000_000;

    /// @dev Issuers and brokers outlive the investors beneath them, as they do in the config.
    ///      Sharing one expiry with the leaves meant that warping past a *leaf* also expired the
    ///      whole tree above it, so a test about re-applying for a lapsed name was really testing
    ///      a collapsed hierarchy.
    uint64 internal constant HIERARCHY_EXPIRY = 4_000_000_000;

    /// @dev `ROLE_REGISTRAR_ADMIN` is not decoration: `grantRootRoles` requires the `_ADMIN` twin
    ///      of the role being granted, so without it the fixture cannot hand the attestor minting
    ///      rights — the same call `DeployIssuerHierarchy.grantAttestor` makes on Sepolia, and the
    ///      same reason `OPERATOR_ROLES` there carries the twins (risk #10).
    uint256 internal constant ROOT_ROLES = RegistryRolesLib.ROLE_REGISTRAR | RegistryRolesLib.ROLE_REGISTRAR_ADMIN
        | RegistryRolesLib.ROLE_SET_PARENT | RegistryRolesLib.ROLE_SET_SUBREGISTRY | RegistryRolesLib.ROLE_SET_RESOLVER
        | RegistryRolesLib.ROLE_RENEW;

    function setUp() public {
        vm.warp(1_000_000_000);

        StubLabelStore labelStore = new StubLabelStore();
        platform = new PermissionedRegistry(ILabelStore(address(labelStore)), address(this), ROOT_ROLES);
        acmeRegistry = new PermissionedRegistry(ILabelStore(address(labelStore)), address(this), ROOT_ROLES);
        zenithRegistry = new PermissionedRegistry(ILabelStore(address(labelStore)), address(this), ROOT_ROLES);
        acmePrime = new PermissionedRegistry(ILabelStore(address(labelStore)), address(this), ROOT_ROLES);
        zenithPrime = new PermissionedRegistry(ILabelStore(address(labelStore)), address(this), ROOT_ROLES);

        _link(platform, acmeRegistry, "acme");
        _link(platform, zenithRegistry, "zenith");
        // The same broker label under both issuers — two names, two registries, two books.
        _link(acmeRegistry, acmePrime, "prime");
        _link(zenithRegistry, zenithPrime, "prime");

        app = new ApplicationContract(IRegistry(address(platform)));
        attestor = new MintAttestor(FORWARDER, IRegistry(address(platform)), address(this));

        acmeChecker = new ENSAllowlistChecker(
            IRegistry(address(platform)), IRegistry(address(acmeRegistry)), ACME_TOKEN, address(this)
        );
        zenithChecker = new ENSAllowlistChecker(
            IRegistry(address(platform)), IRegistry(address(zenithRegistry)), ZENITH_TOKEN, address(this)
        );
        acmeChecker.setAttestor(address(attestor));
        zenithChecker.setAttestor(address(attestor));

        attestor.setChecker(address(acmeRegistry), acmeChecker);
        attestor.setChecker(address(zenithRegistry), zenithChecker);
        attestor.setAllowedWorkflowId(WORKFLOW_ID);

        // The attestor mints directly; there is no separate registrar.
        acmePrime.grantRootRoles(RegistryRolesLib.ROLE_REGISTRAR, address(attestor));
        zenithPrime.grantRootRoles(RegistryRolesLib.ROLE_REGISTRAR, address(attestor));
    }

    /// @dev Both directions. `setSubregistry` alone leaves the child reporting no parent at all,
    ///      which is what the upward walk would stop on.
    function _link(PermissionedRegistry parent, PermissionedRegistry child, string memory label) internal {
        parent.register(label, OWNER, IRegistry(address(child)), address(0), 0, HIERARCHY_EXPIRY);
        child.setParent(IRegistry(address(parent)), label);
    }

    // ── ApplicationContract ──────────────────────────────────────

    function test_brokerPathIsDerivedNotSupplied() public {
        vm.recordLogs();
        vm.prank(ALICE);
        app.submitApplication(address(acmePrime), "alice", 0);

        (address issuer, address broker, string memory path, string memory label, uint8 tier) = _lastApplication();

        assertEq(issuer, address(acmeRegistry), "issuer derived from the tree");
        assertEq(broker, address(acmePrime));
        assertEq(path, "acme/prime", "the rulebook key is a fact, not a claim");
        assertEq(label, "alice");
        assertEq(tier, 0);
    }

    /// @dev The reason the path is derived at all. `prime` exists under both issuers, so a
    ///      caller-supplied string could name `zenith/prime`'s policy while minting into
    ///      `acme/prime`'s registry — evaluated loose, registered strict.
    function test_sameBrokerLabelResolvesPerIssuer() public {
        vm.recordLogs();
        vm.prank(ALICE);
        app.submitApplication(address(acmePrime), "alice", 0);
        (address acmeIssuer,, string memory acmePath,,) = _lastApplication();

        vm.recordLogs();
        vm.prank(BOB);
        app.submitApplication(address(zenithPrime), "bob", 0);
        (address zenithIssuer,, string memory zenithPath,,) = _lastApplication();

        assertEq(acmePath, "acme/prime");
        assertEq(zenithPath, "zenith/prime");
        assertTrue(acmeIssuer != zenithIssuer, "one broker label, two issuers, two policies");
    }

    /// @dev An investor the issuer introduced directly, with no broker in between.
    function test_issuerDirectApplicationHasNoBrokerSegment() public {
        acmeRegistry.grantRootRoles(RegistryRolesLib.ROLE_REGISTRAR, address(attestor));

        vm.recordLogs();
        vm.prank(ALICE);
        app.submitApplication(address(acmeRegistry), "alice", 0);
        (address issuer,, string memory path,,) = _lastApplication();

        assertEq(issuer, address(acmeRegistry));
        assertEq(path, "acme", "resolves to acme/_default with no broker override");
    }

    /// @dev A registry wired downward but never upward reports no parent. Fail closed.
    function test_registryNotUnderPlatformReverts() public {
        StubLabelStore labelStore = new StubLabelStore();
        PermissionedRegistry orphan =
            new PermissionedRegistry(ILabelStore(address(labelStore)), address(this), ROOT_ROLES);

        vm.expectRevert(abi.encodeWithSelector(LibCanopyPath.NotUnderPlatform.selector, address(orphan)));
        vm.prank(ALICE);
        app.submitApplication(address(orphan), "alice", 0);
    }

    function test_walletIsAlwaysMsgSender() public {
        vm.recordLogs();
        vm.prank(ALICE);
        app.submitApplication(address(acmePrime), "alice", 0);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        // topics[2] is the indexed wallet.
        assertEq(address(uint160(uint256(logs[logs.length - 1].topics[2]))), ALICE);
    }

    /// @dev The delegated variant must name the *subject*, not the caller.
    ///
    ///      This has now regressed twice through merges, both times silently: the shared `_submit`
    ///      read `msg.sender` while taking a `wallet` argument it ignored, so every delegated
    ///      application was filed for whoever sent the transaction. It compiles, it emits a
    ///      perfectly well-formed event, and the only symptom is that CRE screens the wrong
    ///      address — which on demo day looks like the engine getting a verdict wrong.
    ///
    ///      Nothing guarded it, which is why it came back. This is that guard.
    function test_delegatedApplicationNamesTheSubjectNotTheCaller() public {
        vm.recordLogs();
        vm.prank(BOB);
        app.submitApplicationFor(ALICE, address(acmePrime), "alice", 0);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(
            address(uint160(uint256(logs[logs.length - 1].topics[2]))),
            ALICE,
            "the application belongs to its subject, not its sender"
        );
    }

    /// @dev And the nonce it consumes is the subject's, so two applications filed on behalf of the
    ///      same wallet get distinct ids even when a single operator sends both.
    function test_delegatedApplicationsForOneWalletGetDistinctIds() public {
        vm.startPrank(BOB);
        bytes32 first = app.submitApplicationFor(ALICE, address(acmePrime), "alice", 0);
        bytes32 second = app.submitApplicationFor(ALICE, address(acmePrime), "alice", 0);
        vm.stopPrank();

        assertTrue(first != second, "per-subject nonce must advance");
    }

    /// @dev Without this the application runs through the enclave and the DON, and only fails when
    ///      the attestor tries to register — after we have paid for the report.
    function test_takenLabelIsRejectedBeforeTheWorkflowRuns() public {
        _mint(address(acmePrime), ALICE, "alice", CanopyRoles.ROLE_ELIGIBLE_SWAP);

        vm.expectRevert(abi.encodeWithSelector(ApplicationContract.LabelTaken.selector, "alice"));
        vm.prank(BOB);
        app.submitApplication(address(acmePrime), "alice", 0);
    }

    function test_expiredLabelMayBeReapplied() public {
        _mint(address(acmePrime), ALICE, "alice", CanopyRoles.ROLE_ELIGIBLE_SWAP);
        vm.warp(EXPIRY + 1);

        vm.prank(BOB);
        app.submitApplication(address(acmePrime), "alice", 0);
    }

    function test_invalidTierAndLabelRevert() public {
        vm.expectRevert(abi.encodeWithSelector(ApplicationContract.InvalidTier.selector, uint8(2)));
        vm.prank(ALICE);
        app.submitApplication(address(acmePrime), "alice", 2);

        vm.expectRevert(ApplicationContract.InvalidLabel.selector);
        vm.prank(ALICE);
        app.submitApplication(address(acmePrime), "", 0);

        // The report carries the label in a bytes32, so 33 characters can never be minted.
        vm.expectRevert(ApplicationContract.InvalidLabel.selector);
        vm.prank(ALICE);
        app.submitApplication(address(acmePrime), "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", 0);
    }

    // ── MintAttestor ─────────────────────────────────────────────

    /// @dev The forwarder asks before it delivers, so getting this wrong means reports are silently
    ///      never sent. It cannot be caught by running the demo: `MockKeystoneForwarder`
    ///      (`0x15fC6ae9…`, what `simulate --broadcast` uses) has no `supportsInterface` call in its
    ///      deployed bytecode, while production `KeystoneForwarder` (`0xF8344CFd…`) does.
    function test_answersERC165ForIReceiver() public view {
        assertTrue(attestor.supportsInterface(type(IReceiver).interfaceId), "IReceiver");
        assertTrue(attestor.supportsInterface(type(IERC165).interfaceId), "IERC165");
        assertFalse(attestor.supportsInterface(0xdeadbeef), "and nothing else");
    }

    /// @dev `IReceiver` declares only `onReport`, so its interfaceId is that selector. Pinning it
    ///      here means an upstream change to the interface breaks the build rather than the demo.
    function test_receiverInterfaceIdIsTheOnReportSelector() public pure {
        assertEq(bytes4(type(IReceiver).interfaceId), IReceiver.onReport.selector);
        assertEq(bytes4(type(IReceiver).interfaceId), bytes4(0x805f2132));
    }

    function test_reportsRejectedUntilWorkflowIdIsSet() public {
        MintAttestor fresh = new MintAttestor(FORWARDER, IRegistry(address(platform)), address(this));

        vm.expectRevert(MintAttestor.WorkflowNotSet.selector);
        vm.prank(FORWARDER);
        fresh.onReport(_metadata(WORKFLOW_ID), _report(ALICE, "alice", address(acmePrime), true));
    }

    function test_onlyForwarderMayDeliver() public {
        vm.expectRevert(abi.encodeWithSelector(MintAttestor.OnlyForwarder.selector, ALICE));
        vm.prank(ALICE);
        attestor.onReport(_metadata(WORKFLOW_ID), _report(ALICE, "alice", address(acmePrime), true));
    }

    function test_wrongWorkflowIsRejected() public {
        bytes32 other = keccak256("someone-elses-workflow");

        vm.expectRevert(abi.encodeWithSelector(MintAttestor.UnexpectedWorkflow.selector, other));
        vm.prank(FORWARDER);
        attestor.onReport(_metadata(other), _report(ALICE, "alice", address(acmePrime), true));
    }

    function test_approvedReportMintsAndGrantsEligibility() public {
        vm.prank(FORWARDER);
        attestor.onReport(_metadata(WORKFLOW_ID), _report(ALICE, "alice", address(acmePrime), true));

        IPermissionedRegistry.State memory state = acmePrime.getState(LibLabel.id("alice"));
        assertEq(uint256(state.status), uint256(IPermissionedRegistry.Status.REGISTERED));
        assertEq(state.latestOwner, ALICE);

        assertEq(
            PermissionFlag.unwrap(acmeChecker.checkAllowlist(ALICE, ACME_TOKEN)),
            PermissionFlag.unwrap(PermissionFlags.SWAP_ALLOWED)
        );
    }

    /// @dev The routing decision. The report says *where to mint*; the chain says *which issuer's
    ///      pool that grants access to*. If the checker came out of the report instead, a bad
    ///      report could put a Zenith investor into Acme's book.
    function test_leafIsRecordedInTheIssuersOwnChecker() public {
        vm.prank(FORWARDER);
        attestor.onReport(_metadata(WORKFLOW_ID), _report(BOB, "bob", address(zenithPrime), true));

        (IPermissionedRegistry zenithLeaf,) = zenithChecker.leafOf(BOB);
        assertEq(address(zenithLeaf), address(zenithPrime), "recorded in Zenith's checker");

        (IPermissionedRegistry acmeLeaf,) = acmeChecker.leafOf(BOB);
        assertEq(address(acmeLeaf), address(0), "and not in Acme's");
    }

    function test_unknownIssuerHasNoChecker() public {
        MintAttestor bare = new MintAttestor(FORWARDER, IRegistry(address(platform)), address(this));
        bare.setAllowedWorkflowId(WORKFLOW_ID);

        vm.expectRevert(abi.encodeWithSelector(MintAttestor.NoCheckerForIssuer.selector, address(acmeRegistry)));
        vm.prank(FORWARDER);
        bare.onReport(_metadata(WORKFLOW_ID), _report(ALICE, "alice", address(acmePrime), true));
    }

    function test_rejectionIsASilentNoop() public {
        vm.prank(FORWARDER);
        attestor.onReport(_metadata(WORKFLOW_ID), _report(ALICE, "alice", address(acmePrime), false));

        IPermissionedRegistry.State memory state = acmePrime.getState(LibLabel.id("alice"));
        assertEq(uint256(state.status), uint256(IPermissionedRegistry.Status.AVAILABLE));
        assertEq(
            PermissionFlag.unwrap(acmeChecker.checkAllowlist(ALICE, ACME_TOKEN)),
            PermissionFlag.unwrap(PermissionFlags.NONE)
        );
    }

    /// @dev `PERMISSIONED_TOKEN` is immutable, so a checker redeployment is routine. It leaves the
    ///      subname registered and the new checker empty; re-delivering the same verdict has to be
    ///      able to repair that rather than see a live name and return early.
    function test_redeliveryRepairsARedeployedChecker() public {
        vm.prank(FORWARDER);
        attestor.onReport(_metadata(WORKFLOW_ID), _report(ALICE, "alice", address(acmePrime), true));

        ENSAllowlistChecker replacement = new ENSAllowlistChecker(
            IRegistry(address(platform)), IRegistry(address(acmeRegistry)), ACME_TOKEN, address(this)
        );
        replacement.setAttestor(address(attestor));
        attestor.setChecker(address(acmeRegistry), replacement);

        assertEq(
            PermissionFlag.unwrap(replacement.checkAllowlist(ALICE, ACME_TOKEN)),
            PermissionFlag.unwrap(PermissionFlags.NONE),
            "the new checker starts empty"
        );

        vm.prank(FORWARDER);
        attestor.onReport(_metadata(WORKFLOW_ID), _report(ALICE, "alice", address(acmePrime), true));

        assertEq(
            PermissionFlag.unwrap(replacement.checkAllowlist(ALICE, ACME_TOKEN)),
            PermissionFlag.unwrap(PermissionFlags.SWAP_ALLOWED),
            "and the same verdict repairs it"
        );
    }

    function test_cannotStealANameHeldBySomeoneElse() public {
        _mint(address(acmePrime), ALICE, "alice", CanopyRoles.ROLE_ELIGIBLE_SWAP);

        vm.expectRevert(abi.encodeWithSelector(MintAttestor.SubnameAlreadyRegistered.selector, BOB));
        vm.prank(FORWARDER);
        attestor.onReport(_metadata(WORKFLOW_ID), _report(BOB, "alice", address(acmePrime), true));
    }

    function test_marketMakerTierGrantsBothBits() public {
        uint256 roles = CanopyRoles.ROLE_ELIGIBLE_SWAP | CanopyRoles.ROLE_ELIGIBLE_LIQUIDITY;

        vm.prank(FORWARDER);
        attestor.onReport(
            _metadata(WORKFLOW_ID),
            abi.encode(uint8(0), ALICE, _label("mm"), address(acmePrime), roles, EXPIRY, true)
        );

        assertEq(
            PermissionFlag.unwrap(acmeChecker.checkAllowlist(ALICE, ACME_TOKEN)),
            PermissionFlag.unwrap(PermissionFlags.SWAP_ALLOWED | PermissionFlags.LIQUIDITY_ALLOWED)
        );
    }

    function test_unsupportedKindReverts() public {
        vm.expectRevert(abi.encodeWithSelector(MintAttestor.UnsupportedKind.selector, uint8(1)));
        vm.prank(FORWARDER);
        attestor.onReport(
            _metadata(WORKFLOW_ID),
            abi.encode(
                uint8(1), ALICE, _label("alice"), address(acmePrime), CanopyRoles.ROLE_ELIGIBLE_SWAP, EXPIRY, true
            )
        );
    }

    function test_shortMetadataReverts() public {
        vm.expectRevert(abi.encodeWithSelector(MintAttestor.MalformedMetadata.selector, uint256(8)));
        vm.prank(FORWARDER);
        attestor.onReport(hex"0011223344556677", _report(ALICE, "alice", address(acmePrime), true));
    }

    // ── helpers ──────────────────────────────────────────────────

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

    function _report(address subject, string memory label, address parentRegistry, bool approved)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(
            uint8(0), subject, _label(label), parentRegistry, CanopyRoles.ROLE_ELIGIBLE_SWAP, EXPIRY, approved
        );
    }

    function _mint(address registry, address owner, string memory label, uint256 roles) internal {
        PermissionedRegistry(registry).register(label, owner, IRegistry(address(0)), address(0), roles, EXPIRY);
    }

    function _lastApplication()
        internal
        view
        returns (address issuer, address broker, string memory brokerPath, string memory label, uint8 tier)
    {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        Vm.Log memory entry = logs[logs.length - 1];
        issuer = address(uint160(uint256(entry.topics[3])));
        (broker, brokerPath, label, tier) = abi.decode(entry.data, (address, string, string, uint8));
    }
}
