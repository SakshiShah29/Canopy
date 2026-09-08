// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IRegistry} from "@ens/registry/interfaces/IRegistry.sol";
import {IPermissionedRegistry} from "@ens/registry/interfaces/IPermissionedRegistry.sol";
import {LibLabel} from "@ens/utils/LibLabel.sol";

/// @notice Minimal stand-in for an ENSv2 `PermissionedRegistry`.
///
/// @dev Implements only the three functions `ENSAllowlistChecker` actually calls — `getState`,
///      `hasRoles` and `getParent` — with signatures matching the real interfaces. The checker
///      reaches registries through interface casts, so selector compatibility is all that is
///      required; declaring `is IPermissionedRegistry` would mean stubbing ~40 unused functions
///      for no added fidelity.
///
///      Deliberately mirrors upstream semantics that the checker depends on:
///        - an expired name reports `Status.AVAILABLE`, not `REGISTERED` (`_constructStatus`)
///        - `hasRoles` is satisfied by a grant on the resource *or* on `ROOT_RESOURCE`
contract MockRegistry {
    uint256 public constant ROOT_RESOURCE = 0;

    struct Entry {
        bool registered;
        uint64 expiry;
        address owner;
        uint256 resource;
    }

    mapping(uint256 labelhash => Entry) internal _entries;
    mapping(uint256 resource => mapping(address account => uint256 roleBitmap)) internal _roles;
    mapping(uint256 labelhash => IRegistry) internal _subregistries;

    IRegistry internal _parent;
    string internal _childLabel;

    // -------------------------------------------------------------------------
    // Test setup helpers
    // -------------------------------------------------------------------------

    /// @notice Register `label` with an absolute `expiry`, giving it a distinct EAC resource.
    function register(string memory label, address owner, uint64 expiry) public returns (uint256 labelhash) {
        labelhash = LibLabel.id(label);
        // Real registries derive the resource from the labelhash and a version counter. Any
        // stable, per-name value reproduces the behaviour the checker relies on.
        _entries[labelhash] = Entry({registered: true, expiry: expiry, owner: owner, resource: labelhash});
    }

    /// @notice Re-register a name under a *fresh* resource, as a version bump does upstream.
    /// @dev This is what orphans a lapsed broker's old role grants.
    function reRegister(string memory label, address owner, uint64 expiry, uint32 versionId)
        external
        returns (uint256 labelhash)
    {
        labelhash = LibLabel.id(label);
        _entries[labelhash] =
            Entry({registered: true, expiry: expiry, owner: owner, resource: LibLabel.withVersion(labelhash, versionId)});
    }

    function grantRoles(uint256 resource, uint256 roleBitmap, address account) external {
        _roles[resource][account] |= roleBitmap;
    }

    function revokeRoles(uint256 resource, uint256 roleBitmap, address account) external {
        _roles[resource][account] &= ~roleBitmap;
    }

    /// @notice Wire the upward pointer, as ENSv2's `setParent` does.
    function setParent(IRegistry parent, string memory label) external {
        _parent = parent;
        _childLabel = label;
    }

    /// @notice Wire the downward delegation, as ENSv2's `setSubregistry` does.
    ///
    /// @dev Deliberately a separate call from `setParent`, exactly as upstream. The two are
    ///      written by different parties — `setParent` by whoever holds roles on the *child*,
    ///      `setSubregistry` by the parent's registrar — and the checker's walk now requires them
    ///      to agree. Wiring both from one helper here would make it impossible to reproduce the
    ///      disagreement, which is the failure the walk is guarding against.
    function setSubregistry(string memory label, IRegistry registry) external {
        _subregistries[LibLabel.id(label)] = registry;
    }

    /// @notice Clear the upward pointer, reproducing a registry wired downward but never upward.
    function clearParent() external {
        _parent = IRegistry(address(0));
        _childLabel = "";
    }

    function expire(string memory label) external {
        _entries[LibLabel.id(label)].expiry = uint64(block.timestamp);
    }

    function unregister(string memory label) external {
        delete _entries[LibLabel.id(label)];
    }

    function resourceOf(string memory label) external view returns (uint256) {
        return _entries[LibLabel.id(label)].resource;
    }

    // -------------------------------------------------------------------------
    // The surface the checker calls
    // -------------------------------------------------------------------------

    function getState(uint256 anyId) external view returns (IPermissionedRegistry.State memory state) {
        Entry storage entry = _entries[anyId];
        state.expiry = entry.expiry;
        state.latestOwner = entry.owner;
        state.tokenId = anyId;
        state.resource = entry.resource;

        if (block.timestamp >= entry.expiry) {
            state.status = IPermissionedRegistry.Status.AVAILABLE;
        } else if (!entry.registered || entry.owner == address(0)) {
            state.status = IPermissionedRegistry.Status.RESERVED;
        } else {
            state.status = IPermissionedRegistry.Status.REGISTERED;
        }
    }

    function hasRoles(uint256 resource, uint256 roleBitmap, address account) external view returns (bool) {
        return (_roles[resource][account] & roleBitmap) == roleBitmap
            || (_roles[ROOT_RESOURCE][account] & roleBitmap) == roleBitmap;
    }

    function getParent() external view returns (IRegistry parent, string memory label) {
        return (_parent, _childLabel);
    }

    function getSubregistry(string calldata label) external view returns (IRegistry) {
        return _subregistries[LibLabel.id(label)];
    }
}

/// @notice A registry that reverts on `getState`, standing in for a hostile or non-registry
///         address appearing in the hierarchy.
contract RevertingRegistry {
    function getState(uint256) external pure returns (IPermissionedRegistry.State memory) {
        revert("not a registry");
    }

    function hasRoles(uint256, uint256, address) external pure returns (bool) {
        return true;
    }

    function getParent() external pure returns (IRegistry, string memory) {
        return (IRegistry(address(0)), "");
    }
}
