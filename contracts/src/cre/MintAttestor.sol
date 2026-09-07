// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IRegistry} from "@ens/registry/interfaces/IRegistry.sol";
import {IPermissionedRegistry} from "@ens/registry/interfaces/IPermissionedRegistry.sol";
import {LibLabel} from "@ens/utils/LibLabel.sol";

import {ENSAllowlistChecker} from "../checker/ENSAllowlistChecker.sol";

// ─── Chainlink CRE IReceiver interface ───────────────────────
// Copied verbatim from Chainlink docs. Implementations must support ERC165.
interface IReceiver is IERC165 {
    function onReport(bytes calldata metadata, bytes calldata report) external;
}

/// @title CRE Report Receiver — mints investor subnames from DON-attested verdicts
///
/// @notice The Chainlink Workflow DON delivers signed reports here via the KeystoneForwarder
///         (`0xF8344CFd5c43616a4366C34E3EEE75af79a74482` on Sepolia).
///
///         Each report encodes a verdict tuple produced inside an AWS Nitro enclave by the
///         canopy-eligibility CRE workflow. If the verdict is APPROVED, this contract:
///
///           1. Registers the investor subname in the broker's registry
///           2. Records the leaf in the ENSAllowlistChecker so the pool recognizes the wallet
///
///         If REJECTED, the call is a no-op (no revert — the DON still needs the tx to settle).
///
/// @dev Security:
///      - `onlyForwarder`: only the KeystoneForwarder can call `onReport`
///      - `allowedWorkflow`: the metadata's workflowId must match the registered workflow
///      - The report tuple is the ONLY data that crosses the enclave confidentiality boundary
///
/// @dev Metadata layout (64 bytes, abi.encodePacked):
///      | Offset | Size | Field          |
///      |--------|------|----------------|
///      | 0-31   | 32   | workflowId     |
///      | 32-41  | 10   | workflowName   |
///      | 42-61  | 20   | workflowOwner  |
///      | 62-63  | 2    | reportId       |
contract MintAttestor is IReceiver {
    // ── Errors ───────────────────────────────────────────────────
    error OnlyForwarder(address caller);
    error UnexpectedWorkflow(bytes32 actual);
    error UnsupportedKind(uint8 kind);

    // ── Events ───────────────────────────────────────────────────
    event VerdictReceived(
        address indexed subject,
        bool    approved,
        uint256 roleBitmap,
        uint64  expiry
    );

    // ── Constants ────────────────────────────────────────────────
    uint8 internal constant KIND_INVESTOR = 0;

    // ── Immutables ───────────────────────────────────────────────
    /// @notice The KeystoneForwarder — the only address that can deliver reports.
    address public immutable forwarder;

    /// @notice The owner who can update configuration.
    address public owner;

    /// @notice The expected CRE workflow ID. Reports from any other workflow are rejected.
    bytes32 public allowedWorkflowId;

    /// @notice The ENSAllowlistChecker that the pool reads for eligibility.
    ENSAllowlistChecker public checker;

    // ── Constructor ──────────────────────────────────────────────
    /// @param _forwarder The KeystoneForwarder address on this chain.
    /// @param _checker   The deployed ENSAllowlistChecker (address(0) if not yet deployed).
    /// @param _owner     The admin who can update allowedWorkflowId.
    constructor(address _forwarder, address _checker, address _owner) {
        forwarder = _forwarder;
        checker = ENSAllowlistChecker(_checker);
        owner = _owner;
    }

    modifier onlyForwarder() {
        if (msg.sender != forwarder) revert OnlyForwarder(msg.sender);
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    // ── ERC165 ────────────────────────────────────────────────────
    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return interfaceId == type(IReceiver).interfaceId
            || interfaceId == type(IERC165).interfaceId;
    }

    // ── Admin ────────────────────────────────────────────────────

    /// @notice Set the allowed CRE workflow ID. Reports from any other workflow are rejected.
    function setAllowedWorkflowId(bytes32 id) external onlyOwner {
        allowedWorkflowId = id;
    }

    /// @notice Update the checker address (in case a new checker is deployed).
    function setChecker(address _checker) external onlyOwner {
        checker = ENSAllowlistChecker(_checker);
    }

    /// @notice Transfer ownership.
    function transferOwnership(address newOwner) external onlyOwner {
        owner = newOwner;
    }

    // ── IReceiver ────────────────────────────────────────────────

    /// @notice Called by the KeystoneForwarder with a DON-signed report.
    /// @param metadata 64 bytes: workflowId (32) || workflowName (10) || workflowOwner (20) || reportId (2)
    /// @param report   ABI-encoded verdict tuple from the enclave.
    function onReport(bytes calldata metadata, bytes calldata report) external override onlyForwarder {
        // ── Validate workflow ID ──
        if (allowedWorkflowId != bytes32(0)) {
            bytes32 workflowId = bytes32(metadata[:32]);
            if (workflowId != allowedWorkflowId) revert UnexpectedWorkflow(workflowId);
        }

        // ── Decode the verdict tuple ──
        // Matches the encodeAbiParameters in workflow.ts exactly:
        //   (uint8 kind, address subject, bytes32 labelBytes, address parentRegistry,
        //    uint256 roleBitmap, uint64 expiry, bool approved)
        (
            uint8   kind,
            address subject,
            bytes32 labelBytes,
            address parentRegistry,
            uint256 roleBitmap,
            uint64  expiry,
            bool    approved
        ) = abi.decode(report, (uint8, address, bytes32, address, uint256, uint64, bool));

        emit VerdictReceived(subject, approved, roleBitmap, expiry);

        // ── REJECT is a silent no-op ──
        if (!approved) return;

        // ── Guard: only investor kind ──
        if (kind != KIND_INVESTOR) revert UnsupportedKind(kind);

        // ── Register the investor subname ──
        string memory label = _bytes32ToString(labelBytes);
        uint256 labelhash = LibLabel.id(label);

        // Idempotent: skip if subname already exists and is alive
        IPermissionedRegistry.State memory state = IPermissionedRegistry(parentRegistry).getState(labelhash);
        if (state.status == IPermissionedRegistry.Status.REGISTERED && state.expiry > block.timestamp) {
            return;
        }

        // Register: label, owner=subject, no subregistry, no resolver, roles, expiry
        IPermissionedRegistry(parentRegistry).register(
            label,
            subject,
            IRegistry(address(0)),  // no sub-subregistry
            address(0),             // no resolver
            roleBitmap,
            expiry
        );

        // ── Record the leaf in the checker ──
        if (address(checker) != address(0)) {
            checker.recordPath(subject, IPermissionedRegistry(parentRegistry), labelhash);
        }
    }

    // ── Helpers ──────────────────────────────────────────────────

    /// @dev Convert a right-padded bytes32 to a string (stops at first null byte).
    function _bytes32ToString(bytes32 b) internal pure returns (string memory) {
        uint256 len = 0;
        while (len < 32 && b[len] != 0) len++;
        bytes memory s = new bytes(len);
        for (uint256 i = 0; i < len; i++) s[i] = b[i];
        return string(s);
    }
}
