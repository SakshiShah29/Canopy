// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";

import {IRegistry} from "@ens/registry/interfaces/IRegistry.sol";

import {ApplicationContract} from "../src/cre/ApplicationContract.sol";
import {MintAttestor} from "../src/cre/MintAttestor.sol";
import {ENSAllowlistChecker} from "../src/checker/ENSAllowlistChecker.sol";

/// @title Deploy the two contracts that bracket the CRE boundary
///
/// @notice `ApplicationContract` is the entrance — an investor's transaction emits the event the
///         workflow triggers on. `MintAttestor` is the exit — the DON delivers its signed verdict
///         there. Everything between the two happens off-chain, inside the enclave.
///
/// @dev Run after `DeployIssuerHierarchy`, which supplies the platform registry and the checkers.
///
///      ```
///      forge script script/DeployCREContracts.s.sol --sig "run()" \
///        --rpc-url $SEPOLIA_RPC_URL --broadcast
///
///      # then, once `cre workflow deploy` has printed the id:
///      forge script script/DeployCREContracts.s.sol --sig "setWorkflow(bytes32)" 0x… \
///        --rpc-url $SEPOLIA_RPC_URL --broadcast
///
///      # and from the hierarchy script, hand the attestor its minting rights:
///      forge script script/DeployIssuerHierarchy.s.sol --sig "grantAttestor(address)" 0x… \
///        --rpc-url $SEPOLIA_RPC_URL --broadcast
///      ```
///
///      Env:
///        DEPLOYER_PRIVATE_KEY  — needs Sepolia ETH
///        KEYSTONE_FORWARDER    — the KeystoneForwarder on Sepolia
contract DeployCREContracts is Script {
    /// @dev Sepolia forwarders, from Chainlink's forwarder directory.
    ///
    ///      **We deliver through the mock, and that is the correct choice, not a shortcut.**
    ///      Confidential workflows are in private beta and support simulation only, so
    ///      `cre workflow simulate --broadcast` is how reports reach Sepolia — and that path uses
    ///      `MockKeystoneForwarder`. The production address is recorded for the day the beta opens;
    ///      nothing in this repo should point at it before then, because a deployed workflow is the
    ///      only thing that delivers through it.
    ///
    ///      The attestor accepts reports from exactly the forwarder it was constructed with, so the
    ///      wrong one here means every report is rejected by `onlyForwarder`.
    address internal constant MOCK_FORWARDER = 0x15fC6ae953E024d975e77382eEeC56A9101f9F88;
    address internal constant PROD_FORWARDER = 0xF8344CFd5c43616a4366C34E3EEE75af79a74482;

    function run() public {
        address deployer = _deployer();

        address forwarder = vm.envOr("KEYSTONE_FORWARDER", MOCK_FORWARDER);
        require(forwarder != address(0), "KEYSTONE_FORWARDER cannot be the zero address");

        if (forwarder == MOCK_FORWARDER) {
            console2.log("forwarder: MockKeystoneForwarder (simulate --broadcast) - expected");
        } else if (forwarder == PROD_FORWARDER) {
            console2.log("forwarder: production KeystoneForwarder.");
            console2.log("  Only a DEPLOYED workflow delivers through this. Confidential workflows");
            console2.log("  are simulation-only in the beta, so reports will not arrive.");
        }

        address platform = _platformRegistry();
        address issuerRegistry = _load("issuerRegistry");
        address checker = _load("checker");

        console2.log("deployer         ", deployer);
        console2.log("forwarder        ", forwarder);
        console2.log("platform registry", platform);

        vm.startBroadcast(_key());

        ApplicationContract app = new ApplicationContract(IRegistry(platform));
        console2.log("ApplicationContract", address(app));

        MintAttestor attestor = new MintAttestor(forwarder, IRegistry(platform), deployer);
        console2.log("MintAttestor       ", address(attestor));

        // Wire the issuer we know about. Multi-issuer deployments call `setChecker(address,address)`
        // once per issuer instead.
        if (issuerRegistry != address(0) && checker != address(0)) {
            attestor.setChecker(issuerRegistry, ENSAllowlistChecker(checker));
            console2.log("checker wired for issuer", issuerRegistry);
        }

        vm.stopBroadcast();

        _save("applicationContract", address(app));
        _save("mintAttestor", address(attestor));

        console2.log("");
        console2.log("NOT YET LIVE. Two things remain, and minting reverts until both are done:");
        console2.log("  1. setWorkflow(bytes32) once `cre workflow deploy` prints the id");
        console2.log("  2. DeployIssuerHierarchy --sig 'grantAttestor(address)'", address(attestor));
    }

    /// @notice Point the attestor at our workflow. Until this runs, every report reverts.
    /// @dev Deliberately a separate phase: the workflow id does not exist until the workflow is
    ///      deployed, and the attestor fails closed rather than accepting anything in the meantime.
    function setWorkflow(bytes32 workflowId) public {
        require(workflowId != bytes32(0), "workflow id required");

        address attestor = _load("mintAttestor");
        require(attestor != address(0), "run run() first");

        vm.startBroadcast(_key());
        MintAttestor(attestor).setAllowedWorkflowId(workflowId);
        vm.stopBroadcast();

        console2.log("allowedWorkflowId set on", attestor);
    }

    /// @notice Point one issuer at the checker that answers for its pool.
    function setChecker(address issuerRegistry, address checker) public {
        address attestor = _load("mintAttestor");
        require(attestor != address(0), "run run() first");
        require(issuerRegistry != address(0) && checker != address(0), "issuer and checker required");

        vm.startBroadcast(_key());
        MintAttestor(attestor).setChecker(issuerRegistry, ENSAllowlistChecker(checker));
        vm.stopBroadcast();
    }

    /// @notice Read back what an operator is most likely to have half-finished.
    function verify() public view {
        address attestor = _load("mintAttestor");
        require(attestor != address(0), "nothing deployed");

        MintAttestor a = MintAttestor(attestor);
        bytes32 wf = a.allowedWorkflowId();

        console2.log("MintAttestor      ", attestor);
        console2.log("forwarder         ", a.FORWARDER());
        console2.log("workflow id set   ", wf != bytes32(0));

        address issuerRegistry = _load("issuerRegistry");
        if (issuerRegistry != address(0)) {
            address wired = address(a.checkerOf(issuerRegistry));
            console2.log("checker for issuer", wired);

            if (wired != address(0)) {
                // The grant that is easiest to forget: the checker has to point back.
                console2.log("checker.attestor  ", ENSAllowlistChecker(wired).attestor());
            }
        }

        require(wf != bytes32(0), "allowedWorkflowId unset: every report will revert");
    }

    // ── helpers ──────────────────────────────────────────────────

    /// @dev The platform root. `DeployIssuerHierarchy` still writes it as `issuerRegistry` while
    ///      the hierarchy is three levels deep; once issuers are their own layer it writes
    ///      `platformRegistry`. Prefer the explicit key and say plainly when falling back, because
    ///      passing the wrong registry here makes `LibCanopyPath` revert on every application with
    ///      an error that looks like a broken hierarchy.
    function _platformRegistry() internal view returns (address platform) {
        platform = _load("platformRegistry");
        if (platform != address(0)) return platform;

        platform = _load("issuerRegistry");
        require(platform != address(0), "run DeployIssuerHierarchy first");
        console2.log("note: no platformRegistry key; using issuerRegistry as the platform root");
    }

    function _key() internal view returns (uint256) {
        return vm.envUint("DEPLOYER_PRIVATE_KEY");
    }

    function _deployer() internal view returns (address) {
        return vm.addr(_key());
    }

    function _deployments() internal view returns (string memory) {
        return vm.envOr("DEPLOYMENTS_PATH", string("../deployments.json"));
    }

    /// @dev Surgical, for the reason spelled out in `DeployIssuerHierarchy._save`. The previous
    ///      version here swallowed every non-address entry in a `catch` and rebuilt the file
    ///      without them — which would have silently deleted Builder B's pool, adapter and token
    ///      addresses the first time this ran against the real `deployments.json`.
    function _save(string memory key, address value) internal {
        string memory path = _deployments();

        try vm.readFile(path) returns (string memory contents) {
            if (bytes(contents).length == 0) vm.writeFile(path, "{}");
        } catch {
            vm.writeFile(path, "{}");
        }

        vm.writeJson(string.concat('"', vm.toString(value), '"'), path, string.concat(".", key));
    }

    function _load(string memory key) internal view returns (address) {
        string memory json = _readDeployments();
        string memory path = string.concat(".", key);
        if (!vm.keyExistsJson(json, path)) return address(0);
        return vm.parseJsonAddress(json, path);
    }

    function _readDeployments() internal view returns (string memory json) {
        try vm.readFile(_deployments()) returns (string memory contents) {
            json = bytes(contents).length == 0 ? "{}" : contents;
        } catch {
            json = "{}";
        }
    }
}
