// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

import {IPermissionsAdapterFactory} from
    "v4-periphery/src/hooks/permissionedPools/interfaces/IPermissionsAdapterFactory.sol";
import {IPermissionsAdapter} from "v4-periphery/src/hooks/permissionedPools/interfaces/IPermissionsAdapter.sol";
import {IAllowlistChecker} from "v4-periphery/src/hooks/permissionedPools/interfaces/IAllowlistChecker.sol";
import {PermissionFlag, PermissionFlags} from "v4-periphery/src/hooks/permissionedPools/libraries/PermissionFlags.sol";

import {CanopyTestToken} from "../src/CanopyTestToken.sol";
import {IssuerAllowlistCheckerFlat} from "../src/checker/IssuerAllowlistCheckerFlat.sol";

/// @title DeployPermissionedPool
/// @notice Deploys the full permissioned pool stack on Sepolia:
///         test token → flat checker → adapter (via factory) → verify → wrappers → pool → enable swapping.
///
/// @dev Run with:
///      forge script script/DeployPermissionedPool.s.sol:DeployPermissionedPool \
///        --rpc-url $SEPOLIA_RPC_URL --broadcast --verify -vvvv
contract DeployPermissionedPool is Script {
    // ──────────────────────────────────────────────────────────────────────
    // Uniswap Permissioned Pools — Sepolia deployed infrastructure
    // ──────────────────────────────────────────────────────────────────────
    IPermissionsAdapterFactory constant FACTORY =
        IPermissionsAdapterFactory(0xE6B0d96919334C33d06266d1420F97f6f434fA2B);
    address constant PERMISSIONED_POSITION_MANAGER = 0xf99D553912084c99F6299291b75Fe9B7119Aa1A7;
    IHooks constant PERMISSIONED_HOOKS = IHooks(0x51247E2291d290d17C08813A175AC86465EdE8c0);
    address constant UNIVERSAL_ROUTER = 0x54C707Df83f03bc9cA64ED2CcF9C99B63FD854b7;
    address constant V4_QUOTER = 0x61B3f2011A92d183C7dbaDBdA940a7555Ccf9227;
    address constant MIXED_ROUTE_QUOTER_V2 = 0x4745F77b56a0E2294426E3936dc4Fab68d9543Cd;

    // 1:1 price — sqrt(1) * 2^96
    uint160 constant SQRT_PRICE_1_1 = 79228162514264337593543950336;

    // Pool params matching Uniswap test conventions
    uint24 constant POOL_FEE = 3000;
    int24 constant TICK_SPACING = 60;

    // How many tokens to mint to the deployer for initial setup + testing
    uint256 constant INITIAL_MINT = 1_000_000e18;

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        console.log("Deployer:", deployer);
        console.log("Factory:", address(FACTORY));

        // Read PoolManager from factory
        address poolManager = FACTORY.POOL_MANAGER();
        console.log("PoolManager:", poolManager);

        vm.startBroadcast(deployerKey);

        // ── Step 1: Deploy the permissioned test token ──────────────────
        CanopyTestToken token = new CanopyTestToken(deployer);
        console.log("CanopyTestToken:", address(token));

        // ── Step 2: Mint initial supply to deployer ─────────────────────
        token.mint(deployer, INITIAL_MINT);

        // ── Step 3: Deploy the flat allowlist checker ────────────────────
        IssuerAllowlistCheckerFlat flatChecker = new IssuerAllowlistCheckerFlat(address(token), deployer);
        console.log("IssuerAllowlistCheckerFlat:", address(flatChecker));

        // Add deployer to the flat checker's allowlist
        flatChecker.setPermission(deployer, PermissionFlags.SWAP_ALLOWED | PermissionFlags.LIQUIDITY_ALLOWED);

        // ── Step 4: Create the permissions adapter via factory ───────────
        address adapterAddr =
            FACTORY.createPermissionsAdapter(IERC20(address(token)), deployer, IAllowlistChecker(address(flatChecker)));
        IPermissionsAdapter adapter = IPermissionsAdapter(adapterAddr);
        console.log("PermissionsAdapter:", adapterAddr);

        // ── Step 5: Allowlist the adapter + infra on the token ──────────
        //   The adapter must be able to RECEIVE the underlying token.
        //   The PermissionedPositionManager receives underlying via
        //   adapter._unwrap during takes, then sweeps to the LP.
        //   The Universal Router may similarly hold underlying briefly.
        token.setAllowlisted(adapterAddr, true);
        token.setAllowlisted(PERMISSIONED_POSITION_MANAGER, true);
        token.setAllowlisted(UNIVERSAL_ROUTER, true);

        // ── Step 6: Verify the adapter ──────────────────────────────────
        //   Approve the adapter to pull 1 wei, deposit it, then verify
        //   via the factory (checks balanceOf(adapter) > 0).
        token.approve(adapterAddr, 1);
        adapter.depositForVerification(1);
        FACTORY.verifyPermissionsAdapter(adapterAddr);
        console.log("Adapter verified");

        // ── Step 7: Register allowed wrappers ───────────────────────────
        //   These contracts need `wrapToPoolManager` access on the adapter.
        //   Missing any of these causes failures that look like checker bugs.
        adapter.updateAllowedWrapper(PERMISSIONED_POSITION_MANAGER, true);
        adapter.updateAllowedWrapper(UNIVERSAL_ROUTER, true);
        adapter.updateAllowedWrapper(V4_QUOTER, true);
        adapter.updateAllowedWrapper(MIXED_ROUTE_QUOTER_V2, true);

        // ── Step 8: Register the permissioned hook ──────────────────────
        adapter.updateAllowedHook(PERMISSIONED_HOOKS, true);

        // ── Step 9: Create the pool ─────────────────────────────────────
        //   Pool trades the adapter (virtual token) against native ETH.
        //   Currency0 < Currency1: ETH (address(0)) is always lowest.
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(address(0)), // native ETH
            currency1: Currency.wrap(adapterAddr), // the adapter
            fee: POOL_FEE,
            tickSpacing: TICK_SPACING,
            hooks: PERMISSIONED_HOOKS
        });

        IPoolManager(poolManager).initialize(poolKey, SQRT_PRICE_1_1);
        console.log("Pool initialized (ETH / adapter)");

        // ── Step 10: Enable swapping ────────────────────────────────────
        //   Swapping is OFF by default. Swaps revert with SwappingDisabled
        //   until the adapter owner explicitly enables it.
        adapter.updateSwappingEnabled(true);
        console.log("Swapping enabled");

        vm.stopBroadcast();

        // ── Summary ─────────────────────────────────────────────────────
        console.log("");
        console.log("=== DEPLOYMENT COMPLETE ===");
        console.log("CanopyTestToken:          ", address(token));
        console.log("IssuerAllowlistCheckerFlat:", address(flatChecker));
        console.log("PermissionsAdapter:       ", adapterAddr);
        console.log("PoolManager:              ", poolManager);
        console.log("Pool: ETH / adapter, fee=3000, tickSpacing=60");
        console.log("");
        console.log("NEXT STEPS:");
        console.log("1. Add deployer addresses to flatChecker.setAllowed()");
        console.log("2. Allowlist investor addresses on the token: token.setAllowlisted(investor, true)");
        console.log("3. Add initial liquidity via PermissionedPositionManager");
        console.log("4. Execute a test swap via the permissioned Universal Router");
        console.log("5. Record all addresses in deployments.json");
    }
}
