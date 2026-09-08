// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IRegistry} from "@ens/registry/interfaces/IRegistry.sol";
import {IPermissionedRegistry} from "@ens/registry/interfaces/IPermissionedRegistry.sol";
import {LibLabel} from "@ens/utils/LibLabel.sol";

import {LibCanopyPath} from "./LibCanopyPath.sol";

/// @title Application entry point for Canopy eligibility
///
/// @notice Investors call `submitApplication` to request eligibility. The CRE workflow watches
///         `ApplicationSubmitted` with a logTrigger and evaluates the applicant inside an AWS
///         Nitro enclave.
///
/// @dev This contract decides nothing, holds nothing and grants nothing — all evaluation happens
///      in the enclave and every state change happens in `MintAttestor` once the DON delivers a
///      signed verdict. What it *does* do is make sure the workflow's inputs are facts rather than
///      claims:
///
///      - **`wallet` is `msg.sender`.** An applicant proves control of the address they are
///        applying for. Accepting it as a parameter would let anyone submit applications naming
///        someone else's wallet.
///      - **`issuer` and `brokerPath` are derived on-chain**, not supplied. `brokerPath` is the key
///        into the confidential rulebook, so a caller who could name it would simply pick the
///        loosest policy in the book — be evaluated under `zenith/_default` while being minted into
///        a broker whose real policy is far stricter. See `LibCanopyPath`.
///      - **The label is checked for collision here**, so an application that could never be
///        minted does not burn a CRE execution and a `writeReport` transaction first.
contract ApplicationContract {
    /// @notice Emitted when an investor submits an eligibility application.
    ///
    /// @dev Contains no PII: triggers run on Workflow DON nodes, outside the enclave. A wallet,
    ///      a registry address and a broker's label path are all public facts already.
    ///
    /// @param applicationId Unique per (sender, nonce) — the mock KYC service keys on it.
    /// @param wallet        The applicant. Always `msg.sender`.
    /// @param issuer        The issuer registry this application is for — **derived**, and
    ///                      therefore which pool the resulting eligibility is good for.
    /// @param broker        The registry the subname would be minted into.
    /// @param brokerPath    Label path used as the rulebook key, e.g. `"acme/prime"` — **derived**.
    /// @param label         The subname the applicant is asking for.
    /// @param requestedTier 0 = retail (swap), 1 = market maker (swap + liquidity). What they ask
    ///                      for; CRE decides what they get, and may approve a lower tier.
    event ApplicationSubmitted(
        bytes32 indexed applicationId,
        address indexed wallet,
        address indexed issuer,
        address broker,
        string brokerPath,
        string label,
        uint8 requestedTier
    );

    error InvalidTier(uint8 requestedTier);
    error InvalidLabel();
    error LabelTaken(string label);

    /// @notice The platform root registry. Every application must resolve up to this.
    IRegistry public immutable PLATFORM_REGISTRY;

    /// @dev Per-sender nonce, so two applications in one block get distinct ids.
    mapping(address applicant => uint256) public nonces;

    constructor(IRegistry platformRegistry) {
        PLATFORM_REGISTRY = platformRegistry;
    }

    /// @notice Submit an eligibility application.
    /// @param broker        The broker's registry to be registered under. Everything else about
    ///                      the applicant's position in the hierarchy is derived from this.
    /// @param label         The subname requested, e.g. `"alice"`.
    /// @param requestedTier 0 = swap only, 1 = swap + liquidity.
    function submitApplication(address broker, string calldata label, uint8 requestedTier)
        external
        returns (bytes32 applicationId)
    {
        return _submit(msg.sender, broker, label, requestedTier);
    }

    /// @notice Submit on behalf of another wallet. **Demo only.**
    ///
    /// @dev The demo needs to file applications for wallets we do not hold keys for — a sanctioned
    ///      address, an address too new to pass the age rule — and those have to be real addresses
    ///      with real on-chain history or the screening step proves nothing.
    ///
    ///      `wallet` is the *only* thing this relaxes. `issuer` and `brokerPath` are still derived
    ///      from `broker`, and the label collision check still runs. The earlier version took the
    ///      issuer and the path as arguments, which quietly undid the guarantee the whole contract
    ///      exists for: `brokerPath` is the rulebook key, so a caller who names it picks which
    ///      policy they are judged under. Anyone could have asked for `zenith/_default`, been
    ///      screened against the loosest rules in the book, and been minted into a broker whose real
    ///      policy is far stricter — with the attestor none the wiser, since it derives the issuer
    ///      itself and would have registered the name exactly as instructed.
    ///
    ///      This must not ship to production as-is: it lets anyone file an application naming
    ///      someone else's wallet. Fine for a testnet demo, an unauthenticated write anywhere else.
    function submitApplicationFor(address wallet, address broker, string calldata label, uint8 requestedTier)
        external
        returns (bytes32 applicationId)
    {
        return _submit(wallet, broker, label, requestedTier);
    }

    function _submit(address wallet, address broker, string calldata label, uint8 requestedTier)
        internal
        returns (bytes32 applicationId)
    {
        if (requestedTier > 1) revert InvalidTier(requestedTier);

        // The report carries the label right-padded into a bytes32, so 32 is a hard ceiling.
        uint256 len = bytes(label).length;
        if (len == 0 || len > 32) revert InvalidLabel();

        (address issuer, string memory brokerPath) = LibCanopyPath.resolve(PLATFORM_REGISTRY, IRegistry(broker));

        // Reject a name that is already live under this broker. Without this the application runs
        // all the way through the enclave and the DON, and only reverts when `MintAttestor` tries
        // to register — after we have paid for the report.
        IPermissionedRegistry.State memory state = IPermissionedRegistry(broker).getState(LibLabel.id(label));
        if (state.status == IPermissionedRegistry.Status.REGISTERED && state.expiry > block.timestamp) {
            revert LabelTaken(label);
        }

        uint256 nonce = nonces[wallet]++;
        applicationId = keccak256(abi.encode(wallet, broker, label, nonce));

        emit ApplicationSubmitted(applicationId, wallet, issuer, broker, brokerPath, label, requestedTier);
    }
}
