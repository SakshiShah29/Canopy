// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console2} from "forge-std/Test.sol";

import {PermissionedRegistry} from "@ens/registry/PermissionedRegistry.sol";
import {IPermissionedRegistry} from "@ens/registry/interfaces/IPermissionedRegistry.sol";
import {ILabelStore} from "@ens/utils/interfaces/ILabelStore.sol";
import {LibLabel} from "@ens/utils/LibLabel.sol";

import {StubLabelStore} from "../mocks/StubLabelStore.sol";

/// @notice Cross-checks Gate 1's local numbers against the live hackathon deployment.
///
/// @dev The Gate 1 benchmark deploys `PermissionedRegistry` from our pinned submodule. The
///      contract actually deployed on Sepolia was built from a different commit — it answers
///      `supportsInterface` for neither `main`'s `IPermissionedRegistry` selector (`0x6be50c69`)
///      nor `feat/permres-inode`'s (`0xafff3a63`) — and may also have been compiled with
///      different optimizer settings. Either would move the real gas.
///
///      `getState` is the per-hop cost driver, so comparing it live against local is what tells
///      us whether the local benchmark transfers. Both are measured against an *unregistered*
///      label: cold SLOAD is priced identically regardless of the value read, and it means the
///      check needs no state we have not created yet.
contract Gate1ForkCrossCheckTest is Test {
    address internal constant LIVE_ETH_REGISTRY = 0x1D78834d97c1D7b1A38c1deDBD1a287cFEd3971e;

    function testFork_getStateCostMatchesLocal() public {
        string memory rpc = vm.envOr("SEPOLIA_RPC_URL", string("https://ethereum-sepolia-rpc.publicnode.com"));
        try vm.createSelectFork(rpc) {}
        catch {
            console2.log("SKIPPED: could not reach Sepolia");
            return;
        }

        uint256 labelhash = LibLabel.id("canopy-gate1-probe");

        uint256 before = gasleft();
        IPermissionedRegistry(LIVE_ETH_REGISTRY).getState(labelhash);
        uint256 live = before - gasleft();

        // Same call against the version we benchmarked, deployed onto the fork.
        PermissionedRegistry local =
            new PermissionedRegistry(ILabelStore(address(new StubLabelStore())), address(this), 0);

        before = gasleft();
        local.getState(labelhash);
        uint256 localCost = before - gasleft();

        console2.log("--- Gate 1 cross-check: cold getState ---");
        console2.log("live Sepolia ETHRegistry ", live);
        console2.log("locally compiled registry", localCost);

        // A modest divergence is expected from differing optimizer settings; a large one would
        // mean the local benchmark does not describe the chain we ship on.
        uint256 diff = live > localCost ? live - localCost : localCost - live;
        assertLt(diff, 5_000, "live getState diverges sharply from the benchmarked build");
    }
}
