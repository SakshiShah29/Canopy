// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title Application entry point for Canopy eligibility
/// @notice Investors call `submitApplication` to request eligibility evaluation.
///         The CRE workflow listens for the `ApplicationSubmitted` event via a logTrigger
///         and processes the application inside an AWS Nitro enclave.
///
/// @dev This contract is intentionally minimal. It emits an event and nothing else — all
///      evaluation logic lives in the CRE enclave, and all on-chain state changes happen
///      in `MintAttestor` after the DON delivers its signed verdict.
contract ApplicationContract {
    /// @notice Emitted when an investor submits an eligibility application.
    /// @param applicationId Unique ID derived from keccak256(sender, block.timestamp, nonce).
    /// @param wallet        The wallet requesting eligibility (indexed for CRE logTrigger).
    /// @param issuer        The issuer whose subname hierarchy governs this pool (indexed).
    /// @param broker        The broker (or issuer itself) under whom the investor will be registered.
    /// @param brokerPath    Slash-separated label path used as the RULEBOOK key (e.g. "acme/prime").
    /// @param requestedTier 0 = retail (swap only), 1 = market maker (swap + liquidity).
    event ApplicationSubmitted(
        bytes32 indexed applicationId,
        address indexed wallet,
        address indexed issuer,
        address broker,
        string  brokerPath,
        uint8   requestedTier
    );

    /// @dev Monotonic nonce per sender to guarantee unique applicationIds even within the same block.
    mapping(address => uint256) public nonces;

    /// @notice Submit an eligibility application.
    /// @param issuer        The issuer address (must match a deployed issuer registry).
    /// @param broker        The broker address (the broker's UserRegistry on-chain).
    /// @param brokerPath    The label path for RULEBOOK lookup (e.g. "acme/prime").
    /// @param requestedTier 0 = swap-only, 1 = swap + liquidity.
    function submitApplication(
        address issuer,
        address broker,
        string calldata brokerPath,
        uint8 requestedTier
    ) external {
        require(requestedTier <= 1, "invalid tier");

        uint256 nonce = nonces[msg.sender]++;
        bytes32 applicationId = keccak256(
            abi.encodePacked(msg.sender, block.timestamp, nonce)
        );

        emit ApplicationSubmitted(
            applicationId,
            msg.sender,
            issuer,
            broker,
            brokerPath,
            requestedTier
        );
    }

    /// @notice Submit on behalf of any wallet — for testing/demo only.
    /// @dev In production, the wallet would always be msg.sender.
    function submitApplicationFor(
        address wallet,
        address issuer,
        address broker,
        string calldata brokerPath,
        uint8 requestedTier
    ) external {
        require(requestedTier <= 1, "invalid tier");

        uint256 nonce = nonces[wallet]++;
        bytes32 applicationId = keccak256(
            abi.encodePacked(wallet, block.timestamp, nonce)
        );

        emit ApplicationSubmitted(
            applicationId,
            wallet,
            issuer,
            broker,
            brokerPath,
            requestedTier
        );
    }
}
