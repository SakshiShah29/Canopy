// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console2} from "forge-std/Test.sol";

/// @notice `deployments.json` is shared: Builder A's scripts write into a file Builder B already
///         owns half of. This asserts writing to it is non-destructive.
///
/// @dev The bug this exists to prevent shipped once. `_save` rebuilt the whole object by iterating
///      top-level keys and re-serializing each as an address, which is only correct while the file
///      is a flat map of addresses — and it never was. Builder B's file carries nested objects
///      (`canopy`, `ens`, `uniswap`, `pool`), a numeric `chainId` and a string `network`.
///
///      It survived review because the fork rehearsal points `DEPLOYMENTS_PATH` at a scratch file
///      that starts as `{}`, so every test wrote into exactly the shape the old code assumed. The
///      first live `commitParent()` would have been the first time it met the real file.
contract DeploymentsAddressBookTest is Test {
    /// @dev A faithful miniature of the real file: a nested object, a number, a string, and a
    ///      top-level address. Each is a different way the old rebuild lost data.
    string internal constant EXISTING = '{'
        '"chainId":11155111,' '"network":"sepolia",' '"deployer":"0xcE1606F346726d8714985b680B84dD6959fb4186",'
        '"canopy":{"CanopyTestToken":"0x0B5Cd086f7A3eadc7419325a3d56Fe338465c920",'
        '"PermissionsAdapter":"0x83b0f98b15c8cDFDbf2C172FD141226f97C649d9"},'
        '"pool":{"fee":3000,"note":"currency0=ETH"}' '}';

    /// @dev One file per test, never a shared one. The EVM is rolled back between tests and the
    ///      filesystem is not, so a shared path means one test's `setUp` rewrites the fixture while
    ///      a sibling is mid-write — which corrupts the JSON and fails both for a reason that has
    ///      nothing to do with what is under test.
    function _fixture(string memory name) internal returns (string memory path) {
        path = string.concat("./out/addressbook-", name, ".json");
        vm.writeFile(path, EXISTING);
    }

    function test_writingOurKeysLeavesBuilderBsEntriesIntact() public {
        string memory path = _fixture("preserve");

        vm.writeJson(string.concat('"', vm.toString(address(0xA11CE)), '"'), path, ".platformRegistry");
        vm.writeJson(string.concat('"', vm.toString(address(0xB0B)), '"'), path, ".registry_acme");

        string memory after_ = vm.readFile(path);

        // Ours landed.
        assertEq(vm.parseJsonAddress(after_, ".platformRegistry"), address(0xA11CE));
        assertEq(vm.parseJsonAddress(after_, ".registry_acme"), address(0xB0B));

        // Builder B's nested objects survived, values and all.
        assertEq(
            vm.parseJsonAddress(after_, ".canopy.CanopyTestToken"),
            0x0B5Cd086f7A3eadc7419325a3d56Fe338465c920,
            "the token address must survive"
        );
        assertEq(
            vm.parseJsonAddress(after_, ".canopy.PermissionsAdapter"),
            0x83b0f98b15c8cDFDbf2C172FD141226f97C649d9,
            "the adapter address must survive"
        );

        // And so did the entries that are not addresses at all — the ones the old rebuild dropped
        // on the floor because `parseJsonAddress` could not read them.
        assertEq(vm.parseJsonUint(after_, ".chainId"), 11155111, "a number must survive");
        assertEq(vm.parseJsonString(after_, ".network"), "sepolia", "a string must survive");
        assertEq(vm.parseJsonUint(after_, ".pool.fee"), 3000, "a nested number must survive");
        assertEq(vm.parseJsonString(after_, ".pool.note"), "currency0=ETH", "a nested string must survive");
    }

    /// @dev Re-running a phase overwrites its own key rather than appending a second one.
    function test_rewritingTheSameKeyIsIdempotent() public {
        string memory path = _fixture("idempotent");

        vm.writeJson(string.concat('"', vm.toString(address(0xA11CE)), '"'), path, ".platformRegistry");
        vm.writeJson(string.concat('"', vm.toString(address(0xDEAD)), '"'), path, ".platformRegistry");

        string memory after_ = vm.readFile(path);
        assertEq(vm.parseJsonAddress(after_, ".platformRegistry"), address(0xDEAD));
        assertEq(vm.parseJsonUint(after_, ".chainId"), 11155111, "and the rest is still there");
    }

    /// @dev The rehearsal's starting state, and a first-ever run on a machine with no file yet.
    function test_worksFromAnEmptyBook() public {
        string memory fresh = "./out/addressbook-fresh.json";
        vm.writeFile(fresh, "{}");
        vm.writeJson(string.concat('"', vm.toString(address(0xA11CE)), '"'), fresh, ".platformRegistry");

        assertEq(vm.parseJsonAddress(vm.readFile(fresh), ".platformRegistry"), address(0xA11CE));
    }
}
