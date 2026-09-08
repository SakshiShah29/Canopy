// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IRegistry} from "@ens/registry/interfaces/IRegistry.sol";

/// @title Derive a registry's position in the Canopy hierarchy from the chain
///
/// @notice Answers two questions about a registry, by walking upward to the platform root:
///         **which issuer does it sit under**, and **what is its label path** (`"acme/prime"`).
///
/// @dev Both answers are used to decide things, so neither may be supplied by a caller.
///
///      - `ApplicationContract` emits the label path, and the CRE workflow uses it as the key
///        into the confidential rulebook. If an applicant could name their own path, they would
///        pick the loosest policy in the book and be evaluated under it while being minted into
///        a stricter broker's registry.
///      - `MintAttestor` uses the issuer registry to choose which checker records the leaf. If
///        that came from the report, a workflow that produced a bad report could also choose
///        which issuer's pool the eligibility lands in.
///
///      Both contracts share this library rather than each walking the tree, because two copies
///      of a security-relevant walk is how they end up disagreeing.
///
///      The walk terminates only by *arriving* at the platform registry — the same fail-closed
///      rule as `ENSAllowlistChecker._ancestorsAlive`, and for the same reason: `setParent` is a
///      separate call from `setSubregistry`, so a registry wired downward but never upward
///      reports no parent at all.
library LibCanopyPath {
    /// @dev Platform → issuer → broker is three, so 8 leaves room and still terminates on a
    ///      cyclic or adversarial parent chain. Matches `ENSAllowlistChecker.MAX_HOPS`.
    uint256 internal constant MAX_DEPTH = 8;

    /// @notice `start` is not reachable from the platform root by following `getParent()`.
    error NotUnderPlatform(address start);

    /// @notice Walk from `start` up to `platform`.
    /// @param platform The platform root registry — the walk must arrive here.
    /// @param start    The registry to locate, typically a broker's registry.
    /// @return issuerRegistry The registry directly beneath `platform` on this path.
    /// @return path           Slash-separated labels from issuer down to `start`, e.g. `"acme/prime"`.
    ///
    /// @dev An investor registered directly under an issuer (no broker) is supported: `start` is
    ///      then the issuer registry itself, and the path is just `"acme"`. The workflow's policy
    ///      lookup takes the segment before the first `/` as the issuer, so `"acme"` resolves to
    ///      `acme/_default` with no broker override — which is the correct answer for a client the
    ///      issuer introduced themselves.
    function resolve(IRegistry platform, IRegistry start)
        internal
        view
        returns (address issuerRegistry, string memory path)
    {
        if (address(start) == address(0) || address(start) == address(platform)) {
            revert NotUnderPlatform(address(start));
        }

        string[] memory labels = new string[](MAX_DEPTH);
        uint256 n;
        IRegistry current = start;

        while (n < MAX_DEPTH && address(current) != address(platform)) {
            (IRegistry parent, string memory label) = current.getParent();
            if (address(parent) == address(0)) revert NotUnderPlatform(address(start));
            // The parent must agree. Without this an impostor registry claims `(acme, "prime")`,
            // is handed Acme's identity and the `acme/prime` rulebook key, and is screened under a
            // policy that has nothing to do with it. See `ENSAllowlistChecker._ancestorsAlive`.
            if (address(parent.getSubregistry(label)) != address(current)) {
                revert NotUnderPlatform(address(start));
            }

            labels[n++] = label;
            // The last registry seen before we reach the platform is the issuer.
            issuerRegistry = address(current);
            current = parent;
        }

        // Terminating anywhere but the platform root is a denial, never a pass.
        if (address(current) != address(platform)) revert NotUnderPlatform(address(start));

        // Labels were collected bottom-up; the path reads top-down.
        path = labels[n - 1];
        for (uint256 i = n - 1; i > 0; i--) {
            path = string.concat(path, "/", labels[i - 1]);
        }
    }

    /// @notice The issuer registry `start` sits under, without building the path string.
    function issuerOf(IRegistry platform, IRegistry start) internal view returns (address issuerRegistry) {
        if (address(start) == address(0) || address(start) == address(platform)) {
            revert NotUnderPlatform(address(start));
        }

        IRegistry current = start;

        for (uint256 hops = 0; hops < MAX_DEPTH; hops++) {
            if (address(current) == address(platform)) return issuerRegistry;

            (IRegistry parent, string memory label) = current.getParent();
            if (address(parent) == address(0)) revert NotUnderPlatform(address(start));
            // Same confirmation as `resolve`. Kept in step deliberately: the two must agree, or
            // an application and the mint that follows it would disagree about the hierarchy.
            if (address(parent.getSubregistry(label)) != address(current)) {
                revert NotUnderPlatform(address(start));
            }

            issuerRegistry = address(current);
            current = parent;
        }

        revert NotUnderPlatform(address(start));
    }
}
