// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";

import {ApplicationContract} from "../src/cre/ApplicationContract.sol";
import {MintAttestor} from "../src/cre/MintAttestor.sol";

/// @title Deploy the CRE infrastructure contracts
///
/// @notice Deploys:
///   1. `ApplicationContract` — emits `ApplicationSubmitted` events that trigger the CRE workflow
///   2. `MintAttestor`        — receives DON-signed verdicts and mints investor subnames
///
/// @dev Required env vars:
///   DEPLOYER_PRIVATE_KEY   — the deployer's private key (needs Sepolia ETH)
///   KEYSTONE_FORWARDER     — the KeystoneForwarder address on Sepolia (or address(1) for testing)
///   CHECKER_ADDRESS        — the ENSAllowlistChecker address (from deployChecker phase)
///
/// Run:
///   forge script script/DeployCREContracts.s.sol:DeployCREContracts \
///     --rpc-url $SEPOLIA_RPC_URL --broadcast -vvvv
contract DeployCREContracts is Script {
    function run() public {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        // The KeystoneForwarder is Chainlink's CRE infrastructure contract on Sepolia.
        // For local testing / simulation, use address(1) as a placeholder.
        address forwarder = vm.envOr("KEYSTONE_FORWARDER", address(1));

        // The ENSAllowlistChecker — if not deployed yet, use address(0) and update later.
        address checkerAddr = vm.envOr("CHECKER_ADDRESS", address(0));

        console2.log("deployer:", deployer);
        console2.log("forwarder:", forwarder);
        console2.log("checker:", checkerAddr);

        vm.startBroadcast(deployerKey);

        // ── 1. ApplicationContract ──
        ApplicationContract app = new ApplicationContract();
        console2.log("ApplicationContract:", address(app));

        // ── 2. MintAttestor ──
        MintAttestor attestor = new MintAttestor(forwarder, checkerAddr, deployer);
        console2.log("MintAttestor:", address(attestor));

        vm.stopBroadcast();

        // ── Save addresses ──
        _save("applicationContract", address(app));
        _save("mintAttestor", address(attestor));
    }

    // ── deployments.json helpers (same pattern as DeployIssuerHierarchy) ──

    function _deployments() internal view returns (string memory) {
        return vm.envOr("DEPLOYMENTS_PATH", string("../deployments.json"));
    }

    function _save(string memory key, address value) internal {
        string memory json = _readDeployments();
        string[] memory keys = vm.parseJsonKeys(json, "$");
        string memory out;
        for (uint256 i = 0; i < keys.length; i++) {
            if (keccak256(bytes(keys[i])) == keccak256(bytes(key))) continue;
            // Preserve existing entries — try address first, fall back to raw
            try vm.parseJsonAddress(json, string.concat(".", keys[i])) returns (address addr) {
                out = vm.serializeAddress("deployments", keys[i], addr);
            } catch {
                // Non-address value (object, number, etc.) — skip, we only deal with flat addresses here
            }
        }
        out = vm.serializeAddress("deployments", key, value);
        vm.writeJson(out, _deployments());
    }

    function _readDeployments() internal view returns (string memory json) {
        try vm.readFile(_deployments()) returns (string memory contents) {
            json = bytes(contents).length == 0 ? "{}" : contents;
        } catch {
            json = "{}";
        }
    }
}
