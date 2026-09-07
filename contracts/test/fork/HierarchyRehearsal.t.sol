// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console2} from "forge-std/Test.sol";

import {IRegistry} from "@ens/registry/interfaces/IRegistry.sol";
import {IPermissionedRegistry} from "@ens/registry/interfaces/IPermissionedRegistry.sol";
import {LibLabel} from "@ens/utils/LibLabel.sol";

import {PermissionFlag, PermissionFlags} from
    "v4-periphery/src/hooks/permissionedPools/libraries/PermissionFlags.sol";

import {DeployIssuerHierarchy} from "../../script/DeployIssuerHierarchy.s.sol";
import {ENSAllowlistChecker} from "../../src/checker/ENSAllowlistChecker.sol";

/// @notice Runs the entire Day 3 deployment against a Sepolia fork before spending a real
///         transaction on it.
///
/// @dev This exists because the live sequence is expensive to debug: the parent registration is
///      commit–reveal with a 60-second gap, several calls are role-gated in ways that fail
///      opaquely, and a mistake in the middle leaves half a hierarchy on-chain that the next run
///      has to reason about. Everything uses the real deployed contracts and real state, so a pass
///      means the only things left to go wrong live are gas and the RPC.
///
///      The one thing a fork cannot rehearse is the *wall-clock* commitment wait; `vm.warp` stands
///      in for it. That is the only difference from what runs on Sepolia.
///
///      The tree under test is the one in `script/hierarchy.json`:
///
///        canopy (platform)
///        ├── acme   ── prime ── alice, mm
///        │          └─ delta
///        └── zenith ── prime ── bob, mm2
///
///      `prime` appears twice on purpose: the same broker onboarded by two issuers. It is what
///      makes containment testable, and it is where a shared proxy salt would collapse two
///      registries into one.
///
/// @dev **This is deliberately a single test function.** The deployment writes its address book to
///      the filesystem and reads configuration from environment variables, and neither is rolled
///      back between tests — while forge runs tests concurrently. Split into several tests, one
///      `setUp` truncates the address book while a sibling is midway through writing it, and
///      `vm.setEnv` (process-wide) leaks whichever value was set last into everyone else. Both
///      present as a phase failing to find something it definitely just deployed, which sends you
///      hunting in entirely the wrong place. One test, built once, with `snapshotState` between
///      scenarios, has neither problem.
contract HierarchyRehearsalTest is Test {
    DeployIssuerHierarchy internal deployScript;

    uint256 internal constant DEPLOYER_KEY = 0xA11CE5EED;
    address internal deployer;

    string internal constant DEPLOYMENTS = "./out/rehearsal-deployments.json";

    address internal constant ETH_REGISTRY = 0x1D78834d97c1D7b1A38c1deDBD1a287cFEd3971e;

    /// @dev Mirrors the script's placeholder derivation for an investor with no configured wallet.
    ///      `script/hierarchy.json` ships with empty wallets, so every bootstrap investor lands on
    ///      one of these.
    function _investor(string memory label) internal view returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked("canopy.investor", label, deployer)))));
    }

    function setUp() public {
        string memory rpc = vm.envOr("SEPOLIA_RPC_URL", string("https://ethereum-sepolia-rpc.publicnode.com"));
        vm.createSelectFork(rpc);

        deployer = vm.addr(DEPLOYER_KEY);
        vm.deal(deployer, 10 ether);

        vm.setEnv("DEPLOYER_PRIVATE_KEY", vm.toString(DEPLOYER_KEY));
        vm.setEnv("DEPLOYMENTS_PATH", DEPLOYMENTS);
        // A label nobody has taken on the shared testnet deployment. The rehearsal registers for
        // real on the fork, so a collision with another team would fail this for the wrong reason.
        vm.setEnv("COMMIT_NONCE", vm.toString(block.timestamp));
        vm.setEnv("BROKER_TTL", vm.toString(uint256(30 days)));
        vm.setEnv("LEAF_TTL", vm.toString(uint256(60 days)));
        vm.writeFile(DEPLOYMENTS, "{}");

        deployScript = new DeployIssuerHierarchy();
    }

    function testFork_day3Rehearsal() public {
        // ── build, in the order deploy-hierarchy.sh runs it ──────────────
        deployScript.commitParent();
        vm.warp(block.timestamp + 61); // the only thing the fork cannot do for real
        deployScript.registerParent();
        deployScript.buildIssuers();
        deployScript.buildHierarchy();
        deployScript.deployCheckers();

        // The end-of-day criterion, including cross-issuer isolation.
        deployScript.verify();

        _assertSetParentWiredAtEveryLevel();

        uint256 built = vm.snapshotState();

        _scenarioCrossIssuerIsolation();
        vm.revertToState(built);

        _scenarioBrokerLapseIsContained();
        vm.revertToState(built);

        _scenarioIssuerLapseCascades();
    }

    // ── scenarios ────────────────────────────────────────────────────────

    /// @dev Beat 9. Eligibility is issuer-scoped, and the proof is a refusal: `alice` is good for
    ///      Acme's pool and must be nothing at all to Zenith's, even though both checkers walk to
    ///      the same platform root. This passes only because the walk must also pass *through*
    ///      `ISSUER_REGISTRY` — drop that guard and every checker admits the whole platform, with
    ///      no happy path anywhere that would notice.
    function _scenarioCrossIssuerIsolation() internal view {
        address alice = _investor("alice"); // acme/prime
        address bob = _investor("bob"); // zenith/prime

        assertEq(_flag("acme", alice), _raw(PermissionFlags.SWAP_ALLOWED), "alice is eligible under acme");
        assertEq(_flag("zenith", alice), _raw(PermissionFlags.NONE), "and must be refused by zenith");

        assertEq(_flag("zenith", bob), _raw(PermissionFlags.SWAP_ALLOWED), "bob is eligible under zenith");
        assertEq(_flag("acme", bob), _raw(PermissionFlags.NONE), "and must be refused by acme");
    }

    /// @dev Beats 11 and 13, which are one event seen from two sides. `acme/prime` lapses: both
    ///      tiers beneath it lose access at the same block, with no transaction sent against
    ///      either and both their own names untouched — and the *same broker* under Zenith keeps
    ///      trading. Without that second half this is indistinguishable from a kill switch.
    ///
    ///      Driven by time rather than by re-deploying with a short TTL: `acme/prime` takes the
    ///      30-day default and `zenith/prime` carries an explicit 90 days in the config, so one
    ///      warp separates them. That is also exactly how the config is meant to be used on camera.
    function _scenarioBrokerLapseIsContained() internal {
        address alice = _investor("alice");
        address mm = _investor("mm");
        address bob = _investor("bob");

        // Precondition for beat 8: the two tiers really differ.
        assertEq(_flag("acme", alice), _raw(PermissionFlags.SWAP_ALLOWED), "retail is swap-only");
        assertEq(
            _flag("acme", mm),
            _raw(PermissionFlags.SWAP_ALLOWED | PermissionFlags.LIQUIDITY_ALLOWED),
            "market maker holds both bits"
        );

        vm.warp(block.timestamp + 31 days);

        assertEq(_flag("acme", alice), _raw(PermissionFlags.NONE), "acme/prime lapsed, retail cut off");
        assertEq(_flag("acme", mm), _raw(PermissionFlags.NONE), "acme/prime lapsed, market maker cut off");

        assertEq(
            _flag("zenith", bob),
            _raw(PermissionFlags.SWAP_ALLOWED),
            "the same broker under zenith must be untouched"
        );

        // Both cut-off investors' own names are still perfectly valid — only the broker expired.
        address acmePrime = _addr("registry_acme_prime");
        string[2] memory labels = ["alice", "mm"];
        for (uint256 i = 0; i < labels.length; i++) {
            IPermissionedRegistry.State memory leaf = IPermissionedRegistry(acmePrime).getState(LibLabel.id(labels[i]));
            assertEq(uint256(leaf.status), uint256(IPermissionedRegistry.Status.REGISTERED));
            assertGt(leaf.expiry, block.timestamp);
        }
    }

    /// @dev The cascade one level up. An issuer lapsing takes every broker and every investor
    ///      beneath it and leaves the other issuer entirely alone — which is why issuers carry a
    ///      long ttl in the config. This is a much bigger event than the one we film.
    function _scenarioIssuerLapseCascades() internal {
        address alice = _investor("alice");
        address mm = _investor("mm");
        address bob = _investor("bob");

        vm.prank(deployer);
        IPermissionedRegistry(_addr("platformRegistry")).unregister(LibLabel.id("acme"));

        assertEq(_flag("acme", alice), _raw(PermissionFlags.NONE), "issuer gone, retail cut off");
        assertEq(_flag("acme", mm), _raw(PermissionFlags.NONE), "issuer gone, market maker cut off");
        assertEq(_flag("zenith", bob), _raw(PermissionFlags.SWAP_ALLOWED), "the other issuer is unaffected");
    }

    /// @dev Guards the trap that `setSubregistry` does not wire the reverse pointer. Checked at all
    ///      three levels, because a registry wired downward but not upward fails only for its own
    ///      subtree — easy to miss while the rest of the tree still works.
    function _assertSetParentWiredAtEveryLevel() internal view {
        (IRegistry platformParent, string memory platformLabel) = IRegistry(_addr("platformRegistry")).getParent();
        assertEq(address(platformParent), ETH_REGISTRY, "platform parent is .eth");
        assertEq(platformLabel, "canopy");

        string[2] memory issuers = ["acme", "zenith"];
        for (uint256 s = 0; s < issuers.length; s++) {
            (IRegistry issuerParent, string memory issuerLabel) =
                IRegistry(_addr(string.concat("registry_", issuers[s]))).getParent();
            assertEq(address(issuerParent), _addr("platformRegistry"), "issuer parent is the platform registry");
            assertEq(issuerLabel, issuers[s]);
        }

        // Every broker, and specifically both `prime`s — where a shared salt or a shared
        // address-book key would show up as one registry doing double duty.
        string[3] memory brokerKeys = ["registry_acme_prime", "registry_acme_delta", "registry_zenith_prime"];
        string[3] memory brokerIssuers = ["registry_acme", "registry_acme", "registry_zenith"];
        string[3] memory brokerLabels = ["prime", "delta", "prime"];

        for (uint256 b = 0; b < brokerKeys.length; b++) {
            (IRegistry brokerParent, string memory brokerLabel) = IRegistry(_addr(brokerKeys[b])).getParent();
            assertEq(address(brokerParent), _addr(brokerIssuers[b]), "broker parent is its own issuer's registry");
            assertEq(brokerLabel, brokerLabels[b]);
        }

        assertTrue(
            _addr("registry_acme_prime") != _addr("registry_zenith_prime"),
            "one broker label under two issuers must not collapse to one registry"
        );
    }

    // NOTE: the "investors must be distinct addresses" guard is deliberately not covered here.
    // Exercising it means mutating an address env var mid-run, and `vm.setEnv` is process-wide —
    // the override would leak into every other assertion in this file.

    // ── helpers ──────────────────────────────────────────────────────────

    /// @dev What `issuer`'s own checker says about `who`, against `issuer`'s own pool token.
    function _flag(string memory issuer, address who) internal view returns (bytes2) {
        ENSAllowlistChecker checker = ENSAllowlistChecker(_addr(string.concat("checker_", issuer)));
        return PermissionFlag.unwrap(
            checker.checkAllowlist(who, _addr(string.concat("permissionedToken_", issuer)))
        );
    }

    function _raw(PermissionFlag f) internal pure returns (bytes2) {
        return PermissionFlag.unwrap(f);
    }

    function _addr(string memory key) internal view returns (address) {
        return vm.parseJsonAddress(vm.readFile(DEPLOYMENTS), string.concat(".", key));
    }
}
