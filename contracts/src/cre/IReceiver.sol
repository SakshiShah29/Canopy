// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @title The interface a Chainlink CRE report receiver must expose
///
/// @dev Vendored rather than imported: Chainlink's `ReceiverTemplate` lives in a repository we do
///      not otherwise depend on, and the docs explicitly sanction implementing `IReceiver`
///      directly — "you control your own security checks". `MintAttestor` needs a workflow-id gate
///      and a fail-closed default that the template does not provide by default, so it does the
///      checks itself and only the interface is shared.
///
///      **ERC-165 is not optional.** `KeystoneForwarder` calls `supportsInterface` before
///      delivering, so a receiver that does not answer never receives a report. This is easy to
///      miss because it does not fail in testing: `MockKeystoneForwarder`
///      (`0x15fC6ae953E024d975e77382eEeC56A9101f9F88`, used by `cre workflow simulate --broadcast`)
///      does **not** make that call, while the production `KeystoneForwarder`
///      (`0xF8344CFd5c43616a4366C34E3EEE75af79a74482`) does — confirmed by reading both deployed
///      bytecodes on Sepolia. A receiver without ERC-165 passes every simulation and then silently
///      receives nothing in production.
interface IReceiver is IERC165 {
    /// @notice Delivers a DON-signed report.
    ///
    /// @param metadata 64 packed bytes describing the workflow that produced the report:
    ///
    ///        | offset | size | field         |
    ///        |--------|------|---------------|
    ///        |   0    |  32  | workflowId    |
    ///        |  32    |  10  | workflowName  |
    ///        |  42    |  20  | workflowOwner |
    ///        |  62    |   2  | reportId      |
    ///
    /// @param report The ABI-encoded payload the workflow produced.
    function onReport(bytes calldata metadata, bytes calldata report) external;
}
