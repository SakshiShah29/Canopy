// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ILabelStore} from "@ens/utils/interfaces/ILabelStore.sol";
import {LibLabel} from "@ens/utils/LibLabel.sol";

/// @notice Test stand-in for ENS's `LabelStore`, faithful to it except for label-size validation.
///
/// @dev `PermissionedRegistry` requires a label store to construct and calls `setLabel` on every
///      registration. The real `LabelStore` imports `NameCoder` from the `ens-contracts`
///      submodule, which we deliberately do not clone — see `remappings.txt`.
///
///      Both behaviours that upstream actually depends on are reproduced:
///        - keys are **truncated**: `withVersion(anyId, 0)` zeroes the low 32 bits, so a versioned
///          token ID and its labelhash resolve to the same entry
///        - `setLabel` is **write-once**, so re-registering a label is an SLOAD, not an SSTORE
///
///      The single divergence is `NameCoder.assertLabelSize`, which is the NameCoder dependency
///      itself. It only rejects oversized labels at registration time; it is not on the
///      `checkAllowlist` path, so Gate 1's numbers are unaffected.
contract StubLabelStore is ILabelStore {
    mapping(uint256 storageId => string label) internal _labels;

    function setLabel(string calldata label) external {
        uint256 labelId = LibLabel.id(label);
        uint256 storageId = _storageId(labelId);
        if (bytes(_labels[storageId]).length == 0) {
            _labels[storageId] = label;
            emit Label(bytes32(labelId), label);
        }
    }

    function getLabel(uint256 anyId) public view returns (string memory) {
        return _labels[_storageId(anyId)];
    }

    function _storageId(uint256 anyId) internal pure returns (uint256) {
        return LibLabel.withVersion(anyId, 0);
    }
}
