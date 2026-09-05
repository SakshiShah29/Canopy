// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {BaseAllowlistChecker} from "v4-periphery/src/hooks/permissionedPools/BaseAllowListChecker.sol";
import {PermissionFlag, PermissionFlags} from
    "v4-periphery/src/hooks/permissionedPools/libraries/PermissionFlags.sol";

import {IRegistry} from "@ens/registry/interfaces/IRegistry.sol";
import {IPermissionedRegistry} from "@ens/registry/interfaces/IPermissionedRegistry.sol";
import {LibLabel} from "@ens/utils/LibLabel.sol";

import {CanopyRoles} from "./CanopyRoles.sol";

/// @title Tiered, expiring pool eligibility derived from an ENSv2 name hierarchy
/// @notice A Uniswap v4 `IAllowlistChecker` that answers "may this account swap / add liquidity?"
///         by walking the ENS hierarchy above the investor's subname.
///
/// @dev **The idea.** An investor holds a subname such as `alice.brokerA.issuer.eth`, with the
///      eligibility roles granted on that subname's EAC resource. Every name on the path up to
///      the root must still be alive for the investor to trade. Revoking a whole broker's book is
///      therefore not a transaction at all — the broker's name simply lapses, and every investor
///      beneath it stops passing this check at the same block. That cascade is the product.
///
/// @dev **Fail-closed.** Every path that is not a positive, fully-verified grant returns
///      `PermissionFlags.NONE`. The one place this matters most is the upward walk: see
///      `_ancestorsAlive`.
contract ENSAllowlistChecker is BaseAllowlistChecker, Ownable {
    /// @notice The leaf name held by an investor: the registry it lives in, and its labelhash.
    struct Leaf {
        IPermissionedRegistry registry;
        uint256 labelhash;
    }

    /// @notice The registry the upward walk must terminate at, i.e. the `.eth` registry.
    /// @dev The walk is only trusted if it *reaches* this. See `_ancestorsAlive`.
    IRegistry public immutable ROOT_ANCHOR;

    /// @notice The permissioned token this checker answers for.
    /// @dev `IAllowlistChecker` passes the token so one checker can serve several assets. We bind
    ///      to exactly one and deny everything else, so attaching this checker to an unrelated
    ///      adapter grants nothing rather than silently reusing another asset's eligibility.
    address public immutable PERMISSIONED_TOKEN;

    /// @dev Bounds the upward walk. Our hierarchy is three deep; 8 leaves room to grow while
    ///      still terminating on a cyclic or adversarial parent chain.
    uint256 public constant MAX_HOPS = 8;

    /// @notice The only address permitted to record paths — the CRE `MintAttestor`.
    address public attestor;

    mapping(address account => Leaf) public leafOf;

    event AttestorUpdated(address indexed attestor);
    event PathRecorded(address indexed account, address indexed registry, uint256 labelhash);

    error NotAttestor(address caller);

    modifier onlyAttestor() {
        if (msg.sender != attestor) revert NotAttestor(msg.sender);
        _;
    }

    constructor(IRegistry rootAnchor, address permissionedToken, address initialOwner) Ownable(initialOwner) {
        ROOT_ANCHOR = rootAnchor;
        PERMISSIONED_TOKEN = permissionedToken;
    }

    /// @notice Point this checker at the attestor that is allowed to record paths.
    function setAttestor(address newAttestor) external onlyOwner {
        attestor = newAttestor;
        emit AttestorUpdated(newAttestor);
    }

    /// @notice Record which leaf name backs `account`'s eligibility.
    /// @dev Called by `MintAttestor` immediately after a subname is minted from a CRE verdict.
    ///      Only the leaf is stored: everything above it is discovered on-chain at check time via
    ///      `getParent()`, so a change in the hierarchy needs no bookkeeping here.
    function recordPath(address account, IPermissionedRegistry registry, uint256 labelhash) external onlyAttestor {
        leafOf[account] = Leaf(registry, labelhash);
        emit PathRecorded(account, address(registry), labelhash);
    }

    /// @inheritdoc BaseAllowlistChecker
    function checkAllowlist(address account, address tokenAddress) public view override returns (PermissionFlag) {
        if (tokenAddress != PERMISSIONED_TOKEN) return PermissionFlags.NONE;

        Leaf memory leaf = leafOf[account];
        if (address(leaf.registry) == address(0)) return PermissionFlags.NONE;

        IPermissionedRegistry.State memory state = leaf.registry.getState(leaf.labelhash);
        if (!_alive(state)) return PermissionFlags.NONE;

        // Roles are read from the leaf only; ancestors confer no permission of their own, they
        // merely have to still exist. Resolving them first lets an ineligible account skip the
        // walk entirely.
        PermissionFlag flag = PermissionFlags.NONE;
        if (leaf.registry.hasRoles(state.resource, CanopyRoles.ROLE_ELIGIBLE_SWAP, account)) {
            flag = flag | PermissionFlags.SWAP_ALLOWED;
        }
        if (leaf.registry.hasRoles(state.resource, CanopyRoles.ROLE_ELIGIBLE_LIQUIDITY, account)) {
            flag = flag | PermissionFlags.LIQUIDITY_ALLOWED;
        }
        if (flag == PermissionFlags.NONE) return PermissionFlags.NONE;

        if (!_ancestorsAlive(leaf.registry)) return PermissionFlags.NONE;

        return flag;
    }

    /// @dev Walks from `start` up to `ROOT_ANCHOR`, requiring every name on the way to be alive.
    ///
    ///      The walk must *arrive* at `ROOT_ANCHOR`. Terminating anywhere else — a null parent, or
    ///      more than `MAX_HOPS` — denies. This is deliberate and load-bearing: ENSv2's
    ///      `setParent` is a separate call from the parent's `setSubregistry`, so a registry that
    ///      was wired downward but never upward reports no parent at all. Treating that as
    ///      "reached the top" would skip every ancestor expiry check and quietly grant a lapsed
    ///      broker's investors permanent access — the exact failure this contract exists to
    ///      prevent, and one that no happy-path test would catch.
    function _ancestorsAlive(IRegistry start) private view returns (bool) {
        IRegistry current = start;

        for (uint256 hops = 0; hops < MAX_HOPS; hops++) {
            if (address(current) == address(ROOT_ANCHOR)) return true;

            (IRegistry parent, string memory label) = current.getParent();
            if (address(parent) == address(0)) return false;

            IPermissionedRegistry.State memory state =
                IPermissionedRegistry(address(parent)).getState(LibLabel.id(label));
            if (!_alive(state)) return false;

            current = parent;
        }

        return false;
    }

    /// @dev A name counts as alive only if it is registered and unexpired.
    ///      `PermissionedRegistry` already collapses an expired name to `AVAILABLE`, so the status
    ///      test alone would do; the explicit expiry comparison keeps this correct against any
    ///      registry implementation that reports the two independently. Note the boundary matches
    ///      upstream `_isExpired`, which treats `block.timestamp == expiry` as expired.
    function _alive(IPermissionedRegistry.State memory state) private view returns (bool) {
        return state.status == IPermissionedRegistry.Status.REGISTERED && state.expiry > block.timestamp;
    }
}
