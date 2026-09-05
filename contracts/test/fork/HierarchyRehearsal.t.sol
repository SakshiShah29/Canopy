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
///      has to reason about. Everything here uses the real deployed contracts and real state, so a
///      pass means the only things left to go wrong live are gas and the RPC.
///
///      The one thing a fork cannot rehearse is the *wall-clock* commitment wait; `vm.warp` stands
///      in for it. That is also the only difference from what runs tomorrow.
contract HierarchyRehearsalTest is Test {
    DeployIssuerHierarchy internal deployScript;

    uint256 internal constant DEPLOYER_KEY = 0xA11CE5EED;
    address internal deployer;

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
        vm.setEnv("DEPLOYMENTS_PATH", "./out/rehearsal-deployments.json");
        // A label nobody has taken on the shared testnet deployment. The rehearsal registers for
        // real on the fork, so a collision with another team would make this fail for the wrong
        // reason.
        vm.setEnv("COMMIT_NONCE", vm.toString(block.timestamp));
        // vm.setEnv is process-wide, so a value set by one test would otherwise leak into the
        // next depending on execution order. Pin the defaults here.
        vm.setEnv("BROKER_TTL", vm.toString(uint256(30 days)));
        vm.setEnv("LEAF_TTL", vm.toString(uint256(60 days)));
        vm.writeFile("./out/rehearsal-deployments.json", "{}");

        deployScript = new DeployIssuerHierarchy();
    }

    function testFork_fullDay3Sequence() public {
        // --- parent: commit, wait, register -------------------------------
        deployScript.commitParent();

        // The only thing the fork cannot do for real.
        vm.warp(block.timestamp + 61);

        deployScript.registerParent();

        // --- hierarchy and checker ----------------------------------------
        deployScript.buildHierarchy();
        deployScript.deployChecker();

        // --- the end-of-day criterion -------------------------------------
        deployScript.verify();
    }

    /// @dev Beat 8, on live contracts rather than mocks: when the broker's name lapses, **both**
    ///      tiers beneath it lose access at the same block — no transaction sent against either,
    ///      and both their own names untouched. One expiry, two revocations that never happened.
    function testFork_brokerLapseCascadesToBothTiers() public {
        deployScript.commitParent();
        vm.warp(block.timestamp + 61);
        deployScript.registerParent();

        vm.setEnv("BROKER_TTL", "600"); // 10 minutes, as on camera
        deployScript.buildHierarchy();
        deployScript.deployChecker();

        ENSAllowlistChecker checker = ENSAllowlistChecker(_addr("checker"));
        address token = _addr("permissionedToken");
        address brokerARegistry = _addr("registry_brokerA");
        address alice = _investor("alice");
        address mm = _investor("mm");
        address bob = _investor("bob"); // under brokerB — must be unaffected

        // Beat 7's precondition: the two tiers really differ.
        assertEq(
            PermissionFlag.unwrap(checker.checkAllowlist(alice, token)),
            PermissionFlag.unwrap(PermissionFlags.SWAP_ALLOWED),
            "retail should be swap-only"
        );
        assertEq(
            PermissionFlag.unwrap(checker.checkAllowlist(mm, token)),
            PermissionFlag.unwrap(PermissionFlags.SWAP_ALLOWED | PermissionFlags.LIQUIDITY_ALLOWED),
            "market maker should hold both bits"
        );

        vm.warp(block.timestamp + 601);

        assertEq(
            PermissionFlag.unwrap(checker.checkAllowlist(alice, token)),
            PermissionFlag.unwrap(PermissionFlags.NONE),
            "brokerA lapsed, retail must be cut off"
        );
        assertEq(
            PermissionFlag.unwrap(checker.checkAllowlist(mm, token)),
            PermissionFlag.unwrap(PermissionFlags.NONE),
            "brokerA lapsed, market maker must be cut off too"
        );

        // The cascade is scoped to the broker that lapsed. brokerB's investor is untouched —
        // otherwise this would be a global kill switch, not an expiry cascade.
        assertEq(
            PermissionFlag.unwrap(checker.checkAllowlist(bob, token)),
            PermissionFlag.unwrap(PermissionFlags.SWAP_ALLOWED),
            "brokerB's investor must be unaffected"
        );

        // Both cut-off investors' own names are still perfectly valid — only the broker expired.
        string[2] memory labels = ["alice", "mm"];
        for (uint256 i = 0; i < labels.length; i++) {
            IPermissionedRegistry.State memory leaf =
                IPermissionedRegistry(brokerARegistry).getState(LibLabel.id(labels[i]));
            assertEq(uint256(leaf.status), uint256(IPermissionedRegistry.Status.REGISTERED));
            assertGt(leaf.expiry, block.timestamp);
        }
    }

    // NOTE: the "investors must be distinct addresses" guard in `buildHierarchy()` is deliberately
    // NOT covered here. Exercising it means mutating MM_ADDRESS mid-test, and `vm.setEnv` is
    // process-wide while forge runs tests in parallel — the override raced into every other test in
    // this file and failed all of them. The guard still protects the real run; a test that
    // corrupts its neighbours is worse than no test.


    /// @dev Guards the trap that `setSubregistry` does not wire the reverse pointer. If the deploy
    ///      script ever stops calling `setParent`, the walk silently loses every ancestor check.
    function testFork_setParentIsWiredBothLevels() public {
        deployScript.commitParent();
        vm.warp(block.timestamp + 61);
        deployScript.registerParent();
        deployScript.buildHierarchy();

        (IRegistry issuerParent, string memory issuerLabel) = IRegistry(_addr("issuerRegistry")).getParent();
        assertEq(address(issuerParent), 0x1D78834d97c1D7b1A38c1deDBD1a287cFEd3971e, "issuer parent must be .eth");
        assertEq(issuerLabel, "canopy");

        // Every broker in the config, not just the first — a second broker wired downward but not
        // upward would fail only for its own investors, which is easy to miss.
        string[2] memory brokers = ["brokerA", "brokerB"];
        for (uint256 i = 0; i < brokers.length; i++) {
            (IRegistry brokerParent, string memory brokerLabel) =
                IRegistry(_addr(string.concat("registry_", brokers[i]))).getParent();
            assertEq(address(brokerParent), _addr("issuerRegistry"), "broker parent must be the issuer registry");
            assertEq(brokerLabel, brokers[i]);
        }
    }

    function _addr(string memory key) internal view returns (address) {
        string memory json = vm.readFile("./out/rehearsal-deployments.json");
        return vm.parseJsonAddress(json, string.concat(".", key));
    }
}
