// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title CanopyTestToken
/// @notice A permissioned ERC-20 for the Canopy hackathon demo.
/// @dev Only allowlisted addresses may *receive* tokens (`_update` gate on `to`).
///      This models a real-world transfer-restricted security: the issuer controls
///      who can hold the asset, and the Uniswap PermissionsAdapter must be on the
///      allowlist before it can custody the underlying token.
contract CanopyTestToken is ERC20, Ownable {
    mapping(address account => bool) public isAllowlisted;

    error NotAllowlisted(address account);

    event Allowlisted(address indexed account, bool status);

    constructor(address initialOwner)
        ERC20("Canopy Test Token", "cTKN")
        Ownable(initialOwner)
    {
        isAllowlisted[initialOwner] = true;
        emit Allowlisted(initialOwner, true);
    }

    /// @notice Mint tokens to an allowlisted address.
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    /// @notice Set the allowlist status for a single address.
    function setAllowlisted(address account, bool status) external onlyOwner {
        isAllowlisted[account] = status;
        emit Allowlisted(account, status);
    }

    /// @notice Batch-set allowlist status.
    function setAllowlistedBatch(address[] calldata accounts, bool status) external onlyOwner {
        for (uint256 i; i < accounts.length; ++i) {
            isAllowlisted[accounts[i]] = status;
            emit Allowlisted(accounts[i], status);
        }
    }

    /// @dev Gate: only allowlisted addresses may receive tokens.
    ///      Burns (to == address(0)) are always permitted.
    function _update(address from, address to, uint256 amount) internal override {
        if (to != address(0) && !isAllowlisted[to]) revert NotAllowlisted(to);
        super._update(from, to, amount);
    }
}
