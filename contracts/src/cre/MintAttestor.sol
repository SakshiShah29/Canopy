// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IRegistry} from "@ens/registry/interfaces/IRegistry.sol";
import {IPermissionedRegistry} from "@ens/registry/interfaces/IPermissionedRegistry.sol";
import {LibLabel} from "@ens/utils/LibLabel.sol";

import {ENSAllowlistChecker} from "../checker/ENSAllowlistChecker.sol";
import {IReceiver} from "./IReceiver.sol";
import {LibCanopyPath} from "./LibCanopyPath.sol";

/// @title CRE report receiver — mints investor subnames from DON-attested verdicts
///
/// @notice The Chainlink Workflow DON delivers signed reports here through the KeystoneForwarder.
///         Each report carries a verdict produced inside an AWS Nitro enclave. On APPROVE this
///         contract registers the investor's subname in the broker's registry and records the leaf
///         in that **issuer's** checker. On REJECT it is a silent no-op — the DON still needs the
///         transaction to settle, so reverting would be wrong.
///
/// @dev Three boundaries, in the order they are checked:
///      1. `onlyForwarder` — only the KeystoneForwarder may deliver.
///      2. `allowedWorkflowId` — the report must come from *our* workflow. `ReceiverTemplate`
///         decodes metadata but does not validate it, so this check is ours to add: without it any
///         workflow routed through the same forwarder could mint subnames.
///      3. `kind` — a decode guard. `abi.decode` of a differently shaped payload can succeed and
///         yield garbage rather than revert, so the shape is asserted before it is acted on.
///
///      Implements `IReceiver` directly rather than inheriting Chainlink's `ReceiverTemplate`,
///      which the docs sanction ("you control your own security checks") and which avoids vendoring
///      a repository we do not otherwise depend on. The one thing that cannot be skipped is
///      **ERC-165** — see `IReceiver` for why its absence is invisible in simulation.
contract MintAttestor is IReceiver {
    // ── Errors ───────────────────────────────────────────────────
    error OnlyForwarder(address caller);
    error WorkflowNotSet();
    error UnexpectedWorkflow(bytes32 actual);
    error MalformedMetadata(uint256 length);
    error UnsupportedKind(uint8 kind);
    error SubnameAlreadyRegistered(address subject);
    error NoCheckerForIssuer(address issuerRegistry);
    error NotOwner(address caller);

    // ── Events ───────────────────────────────────────────────────
    event VerdictReceived(address indexed subject, bool approved, uint256 roleBitmap, uint64 expiry);
    event SubnameMinted(address indexed subject, address indexed parentRegistry, address indexed issuerRegistry);
    event CheckerSet(address indexed issuerRegistry, address checker);
    event AllowedWorkflowIdSet(bytes32 workflowId);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    // ── Constants ────────────────────────────────────────────────
    uint8 internal constant KIND_INVESTOR = 0;

    // ── Immutables ───────────────────────────────────────────────
    /// @notice The KeystoneForwarder — the only address that can deliver reports.
    address public immutable FORWARDER;

    /// @notice The platform root registry, used to locate a broker's issuer. See `LibCanopyPath`.
    IRegistry public immutable PLATFORM_REGISTRY;

    // ── Storage ──────────────────────────────────────────────────
    address public owner;

    /// @notice The CRE workflow permitted to mint. **Reports are rejected until this is set.**
    bytes32 public allowedWorkflowId;

    /// @notice One checker per issuer — eligibility is issuer-scoped, so the leaf has to be
    ///         recorded in the checker that answers for that issuer's pool.
    mapping(address issuerRegistry => ENSAllowlistChecker) public checkerOf;

    constructor(address forwarder, IRegistry platformRegistry, address initialOwner) {
        FORWARDER = forwarder;
        PLATFORM_REGISTRY = platformRegistry;
        owner = initialOwner;
        emit OwnershipTransferred(address(0), initialOwner);
    }

    modifier onlyForwarder() {
        if (msg.sender != FORWARDER) revert OnlyForwarder(msg.sender);
        _;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner(msg.sender);
        _;
    }

    // ── Admin ────────────────────────────────────────────────────

    /// @notice Set the workflow permitted to mint. Until this is called, every report reverts.
    function setAllowedWorkflowId(bytes32 id) external onlyOwner {
        allowedWorkflowId = id;
        emit AllowedWorkflowIdSet(id);
    }

    /// @notice Point an issuer at the checker that answers for its pool.
    /// @dev The checker must also be pointed back here with `ENSAllowlistChecker.setAttestor`,
    ///      since `recordPath` is `onlyAttestor`. That call is the checker owner's to make — it
    ///      cannot be done from here, and forgetting it is the most likely way to break minting.
    function setChecker(address issuerRegistry, ENSAllowlistChecker checker) external onlyOwner {
        checkerOf[issuerRegistry] = checker;
        emit CheckerSet(issuerRegistry, address(checker));
    }

    function transferOwnership(address newOwner) external onlyOwner {
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    // ── ERC-165 ──────────────────────────────────────────────────

    /// @inheritdoc IERC165
    /// @dev `KeystoneForwarder` calls this before delivering, and skips receivers that do not
    ///      answer `true` for `IReceiver`. Omitting it is invisible until production: the mock
    ///      forwarder used by `cre workflow simulate --broadcast` never asks.
    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return interfaceId == type(IReceiver).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    // ── Report receiver ──────────────────────────────────────────

    /// @inheritdoc IReceiver
    /// @param metadata Packed workflow identity; see `IReceiver` for the full 64-byte layout. Only
    ///                 the leading `workflowId` is read — `workflowName`, `workflowOwner` and
    ///                 `reportId` sit at offsets 32, 42 and 62 if they are ever wanted.
    /// @param report   ABI-encoded verdict tuple from the enclave.
    function onReport(bytes calldata metadata, bytes calldata report) external onlyForwarder {
        // ── 1. The report must come from our workflow ──
        // Fail closed: an unset id rejects everything rather than accepting everything. There is a
        // window between deploying this contract and registering the workflow, and during it a
        // permissive default would let any workflow on the same forwarder mint subnames.
        if (allowedWorkflowId == bytes32(0)) revert WorkflowNotSet();
        // 32, not the full 64: the workflow id is all we validate, and requiring more than we read
        // would make this depend on the mock and production forwarders packing metadata
        // identically — which is exactly the kind of difference that shows up only in production.
        if (metadata.length < 32) revert MalformedMetadata(metadata.length);

        bytes32 workflowId = bytes32(metadata[:32]);
        if (workflowId != allowedWorkflowId) revert UnexpectedWorkflow(workflowId);

        // ── 2. Decode the verdict ──
        // Must match `encodeAbiParameters` in cre/eligibility-workflow/workflow.ts exactly.
        (
            uint8 kind,
            address subject,
            bytes32 labelBytes,
            address parentRegistry,
            uint256 roleBitmap,
            uint64 expiry,
            bool approved
        ) = abi.decode(report, (uint8, address, bytes32, address, uint256, uint64, bool));

        emit VerdictReceived(subject, approved, roleBitmap, expiry);

        // A rejection is a no-op on-chain. Nothing is written, and the transaction still settles.
        if (!approved) return;

        if (kind != KIND_INVESTOR) revert UnsupportedKind(kind);

        // ── 3. Which issuer's checker? Ask the chain, not the report ──
        // The report chooses where the name is minted; the hierarchy above that registry decides
        // which pool the eligibility is good for. Reading the issuer here rather than trusting a
        // field means a workflow that produced a bad report still cannot direct eligibility into
        // an unrelated issuer's pool.
        address issuerRegistry = LibCanopyPath.issuerOf(PLATFORM_REGISTRY, IRegistry(parentRegistry));
        ENSAllowlistChecker checker = checkerOf[issuerRegistry];
        if (address(checker) == address(0)) revert NoCheckerForIssuer(issuerRegistry);

        // ── 4. Register the subname, unless it is already live ──
        string memory label = _bytes32ToString(labelBytes);
        uint256 labelhash = LibLabel.id(label);

        IPermissionedRegistry registry = IPermissionedRegistry(parentRegistry);
        IPermissionedRegistry.State memory state = registry.getState(labelhash);

        bool alive = state.status == IPermissionedRegistry.Status.REGISTERED && state.expiry > block.timestamp;

        if (alive) {
            // Someone else already holds this name under this broker. `ApplicationContract` rejects
            // this case up front, so reaching it means the name was taken between application and
            // delivery.
            if (state.latestOwner != subject) revert SubnameAlreadyRegistered(subject);
        } else {
            registry.register(
                label,
                subject,
                IRegistry(address(0)), // an investor leaf has no subregistry
                address(0), // and no resolver
                roleBitmap,
                expiry
            );
        }

        // ── 5. Record the leaf ──
        // Deliberately outside the branch above. A checker redeployment (PERMISSIONED_TOKEN is
        // immutable, so it happens) leaves the name registered but the new checker empty; running
        // the same verdict again must be able to repair that rather than return early.
        checker.recordPath(subject, registry, labelhash);

        emit SubnameMinted(subject, parentRegistry, issuerRegistry);
    }

    // ── Helpers ──────────────────────────────────────────────────

    /// @dev Right-padded `bytes32` back to a string. The report is a flat tuple and `register`
    ///      needs a `string`, so the label travels as itself rather than as a hash — a hash could
    ///      not be reversed. Trailing zero bytes are the padding.
    function _bytes32ToString(bytes32 b) internal pure returns (string memory) {
        uint256 len;
        while (len < 32 && b[len] != 0) len++;

        bytes memory s = new bytes(len);
        for (uint256 i = 0; i < len; i++) {
            s[i] = b[i];
        }
        return string(s);
    }
}
