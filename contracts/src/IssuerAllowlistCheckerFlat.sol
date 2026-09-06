// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseAllowlistChecker} from "v4-periphery/src/hooks/permissionedPools/BaseAllowlistChecker.sol";
import {PermissionFlag, PermissionFlags} from "v4-periphery/src/hooks/permissionedPools/libraries/PermissionFlags.sol";

/// @title IssuerAllowlistCheckerFlat
/// @notice A flat (non-hierarchical) allowlist checker used as a gas-comparison
///         baseline against the ENS-backed ENSAllowlistChecker.
/// @dev The owner can add/remove addresses. Every allowed address receives
///      ALL_ALLOWED.  This mirrors the simplest possible IAllowlistChecker
///      implementation for benchmark purposes.
contract IssuerAllowlistCheckerFlat is BaseAllowlistChecker {
    address public immutable owner;

    mapping(address => bool) public allowed;

    error Unauthorized();

    event AllowlistUpdated(address indexed account, bool status);

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    constructor(address _owner) {
        owner = _owner;
    }

    /// @notice Batch-set allowlist status for multiple accounts.
    function setAllowed(address[] calldata accounts, bool status) external onlyOwner {
        for (uint256 i; i < accounts.length; ++i) {
            allowed[accounts[i]] = status;
            emit AllowlistUpdated(accounts[i], status);
        }
    }

    /// @inheritdoc BaseAllowlistChecker
    function checkAllowlist(address account, address /* tokenAddress */)
        public
        view
        override
        returns (PermissionFlag)
    {
        return allowed[account] ? PermissionFlags.ALL_ALLOWED : PermissionFlags.NONE;
    }
}
