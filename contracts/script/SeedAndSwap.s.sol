// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";

import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {IV4Router} from "v4-periphery/src/interfaces/IV4Router.sol";
import {Actions} from "v4-periphery/src/libraries/Actions.sol";
import {ActionConstants} from "v4-periphery/src/libraries/ActionConstants.sol";
import {IPermissionsAdapter} from "v4-periphery/src/hooks/permissionedPools/interfaces/IPermissionsAdapter.sol";

import {IssuerAllowlistCheckerFlat} from "../src/checker/IssuerAllowlistCheckerFlat.sol";

/// @title SeedAndSwap
/// @notice Seeds initial liquidity into the permissioned pool and executes a test swap.
///         Run AFTER DeployPermissionedPool has been broadcast.
///
/// @dev Required env vars:
///      DEPLOYER_PRIVATE_KEY — same deployer that ran the deployment script
///      TOKEN_ADDRESS        — CanopyTestToken address
///      ADAPTER_ADDRESS      — PermissionsAdapter address
///      CHECKER_ADDRESS      — IssuerAllowlistCheckerFlat address
///
/// @dev Run with:
///      forge script script/SeedAndSwap.s.sol:SeedAndSwap \
///        --rpc-url $SEPOLIA_RPC_URL --broadcast -vvvv
contract SeedAndSwap is Script {
    // ──────────────────────────────────────────────────────────────────────
    // Uniswap Permissioned Pools — Sepolia
    // ──────────────────────────────────────────────────────────────────────
    address constant PERMISSIONED_POSITION_MANAGER = 0xf99D553912084c99F6299291b75Fe9B7119Aa1A7;
    IHooks constant PERMISSIONED_HOOKS = IHooks(0x51247E2291d290d17C08813A175AC86465EdE8c0);
    address constant UNIVERSAL_ROUTER = 0x54C707Df83f03bc9cA64ED2CcF9C99B63FD854b7;

    // Canonical Permit2 (same on every chain)
    IAllowanceTransfer constant PERMIT2 = IAllowanceTransfer(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    // Pool constants (must match DeployPermissionedPool)
    uint24 constant POOL_FEE = 3000;
    int24 constant TICK_SPACING = 60;
    uint160 constant SQRT_PRICE_1_1 = 79228162514264337593543950336;

    // Full-range tick bounds, multiples of TICK_SPACING
    int24 constant TICK_LOWER = -887220;
    int24 constant TICK_UPPER = 887220;

    // Seed liquidity amounts (both 18 decimals, 1:1 pool)
    uint256 constant SEED_ETH = 0.01 ether;
    uint256 constant SEED_TOKEN = 0.01 ether;

    // Test swap amount
    uint256 constant SWAP_ETH_IN = 0.001 ether;

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        address tokenAddr = vm.envAddress("TOKEN_ADDRESS");
        address adapterAddr = vm.envAddress("ADAPTER_ADDRESS");

        console.log("Deployer:", deployer);
        console.log("Token:", tokenAddr);
        console.log("Adapter:", adapterAddr);

        // Reconstruct the pool key
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(adapterAddr),
            fee: POOL_FEE,
            tickSpacing: TICK_SPACING,
            hooks: PERMISSIONED_HOOKS
        });

        vm.startBroadcast(deployerKey);

        // ════════════════════════════════════════════════════════════════
        // PART 1: Seed liquidity
        // ════════════════════════════════════════════════════════════════

        // 1a. Approve Permit2 on the underlying token (infinite approval)
        IERC20(tokenAddr).approve(address(PERMIT2), type(uint256).max);

        // 1b. Approve PermissionedPositionManager as Permit2 spender
        PERMIT2.approve(tokenAddr, PERMISSIONED_POSITION_MANAGER, type(uint160).max, type(uint48).max);

        // 1c. Compute liquidity from desired amounts
        uint128 liquidity = _getLiquidityForAmounts(
            SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(TICK_LOWER),
            TickMath.getSqrtPriceAtTick(TICK_UPPER),
            SEED_ETH,
            SEED_TOKEN
        );
        console.log("Liquidity to mint:", uint256(liquidity));

        // 1d. Build the MINT_POSITION plan
        //     Actions: MINT_POSITION → SETTLE_PAIR
        //     SETTLE_PAIR auto-handles native ETH (from msg.value) vs
        //     ERC-20 (pulled from user via Permit2).
        bytes memory mintPlan;
        {
            bytes memory actions = abi.encodePacked(
                uint8(Actions.MINT_POSITION),
                uint8(Actions.SETTLE_PAIR)
            );

            bytes[] memory params = new bytes[](2);
            params[0] = abi.encode(
                poolKey,
                TICK_LOWER,
                TICK_UPPER,
                liquidity,
                type(uint128).max, // amount0Max — generous slippage for seed
                type(uint128).max, // amount1Max
                deployer,          // recipient (caller == recipient for LIQUIDITY_ALLOWED)
                bytes("")          // hookData
            );
            params[1] = abi.encode(poolKey.currency0, poolKey.currency1);

            mintPlan = abi.encode(actions, params);
        }

        // 1e. Execute the mint — send ETH for the native side
        IPositionManager(PERMISSIONED_POSITION_MANAGER).modifyLiquidities{value: SEED_ETH}(
            mintPlan,
            block.timestamp + 3600
        );
        console.log("Liquidity seeded: ETH =", SEED_ETH, "TOKEN =", SEED_TOKEN);

        // ════════════════════════════════════════════════════════════════
        // PART 2: Test swap (ETH → permissioned token)
        // ════════════════════════════════════════════════════════════════

        // 2a. Approve Permit2 spender for the router (needed for output)
        PERMIT2.approve(tokenAddr, UNIVERSAL_ROUTER, type(uint160).max, type(uint48).max);

        // 2b. Build the V4_SWAP plan
        //     SWAP_EXACT_IN_SINGLE → SETTLE_ALL (ETH input) → TAKE_ALL (token output)
        bytes memory swapPlan;
        {
            bytes memory actions = abi.encodePacked(
                uint8(Actions.SWAP_EXACT_IN_SINGLE),
                uint8(Actions.SETTLE_ALL),
                uint8(Actions.TAKE_ALL)
            );

            bytes[] memory params = new bytes[](3);
            params[0] = abi.encode(
                IV4Router.ExactInputSingleParams({
                    poolKey: poolKey,
                    zeroForOne: true,        // ETH → adapter
                    amountIn: uint128(SWAP_ETH_IN),
                    amountOutMinimum: 0,     // no slippage protection for test
                    minHopPriceX36: 0,
                    hookData: bytes("")
                })
            );
            // SETTLE_ALL: settle input currency (ETH) — max amount = unlimited
            params[1] = abi.encode(poolKey.currency0, type(uint256).max);
            // TAKE_ALL: take output currency (adapter) — min amount = 0
            params[2] = abi.encode(poolKey.currency1, uint256(0));

            swapPlan = abi.encode(actions, params);
        }

        // 2c. Execute via Universal Router — command 0x10 = V4_SWAP
        bytes memory commands = hex"10";
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = swapPlan;

        // Record token balance before swap
        uint256 tokenBalBefore = IERC20(tokenAddr).balanceOf(deployer);

        (bool success,) = UNIVERSAL_ROUTER.call{value: SWAP_ETH_IN}(
            abi.encodeWithSignature(
                "execute(bytes,bytes[],uint256)",
                commands,
                inputs,
                block.timestamp + 3600
            )
        );
        require(success, "Swap failed");

        uint256 tokenBalAfter = IERC20(tokenAddr).balanceOf(deployer);
        uint256 received = tokenBalAfter - tokenBalBefore;

        console.log("Swap executed: sent", SWAP_ETH_IN, "wei ETH");
        console.log("Received", received, "wei cTKN");

        vm.stopBroadcast();

        console.log("");
        console.log("=== SEED AND SWAP COMPLETE ===");
        console.log("Pool has liquidity and swapping is verified.");
    }

    /// @dev Compute liquidity for given amounts at a 1:1 full-range position.
    ///      Simplified from Uniswap's LiquidityAmounts — avoids importing test-only contracts.
    function _getLiquidityForAmounts(
        uint160 sqrtPriceX96,
        uint160 sqrtPriceAX96,
        uint160 sqrtPriceBX96,
        uint256 amount0,
        uint256 amount1
    ) internal pure returns (uint128 liquidity) {
        if (sqrtPriceAX96 > sqrtPriceBX96) {
            (sqrtPriceAX96, sqrtPriceBX96) = (sqrtPriceBX96, sqrtPriceAX96);
        }

        if (sqrtPriceX96 <= sqrtPriceAX96) {
            liquidity = _getLiquidityForAmount0(sqrtPriceAX96, sqrtPriceBX96, amount0);
        } else if (sqrtPriceX96 < sqrtPriceBX96) {
            uint128 liquidity0 = _getLiquidityForAmount0(sqrtPriceX96, sqrtPriceBX96, amount0);
            uint128 liquidity1 = _getLiquidityForAmount1(sqrtPriceAX96, sqrtPriceX96, amount1);
            liquidity = liquidity0 < liquidity1 ? liquidity0 : liquidity1;
        } else {
            liquidity = _getLiquidityForAmount1(sqrtPriceAX96, sqrtPriceBX96, amount1);
        }
    }

    function _getLiquidityForAmount0(uint160 sqrtPriceAX96, uint160 sqrtPriceBX96, uint256 amount0)
        private
        pure
        returns (uint128)
    {
        if (sqrtPriceAX96 > sqrtPriceBX96) {
            (sqrtPriceAX96, sqrtPriceBX96) = (sqrtPriceBX96, sqrtPriceAX96);
        }
        uint256 intermediate = uint256(sqrtPriceAX96) * sqrtPriceBX96 / (1 << 96);
        return uint128(amount0 * intermediate / (sqrtPriceBX96 - sqrtPriceAX96));
    }

    function _getLiquidityForAmount1(uint160 sqrtPriceAX96, uint160 sqrtPriceBX96, uint256 amount1)
        private
        pure
        returns (uint128)
    {
        if (sqrtPriceAX96 > sqrtPriceBX96) {
            (sqrtPriceAX96, sqrtPriceBX96) = (sqrtPriceBX96, sqrtPriceAX96);
        }
        return uint128(amount1 * (1 << 96) / (sqrtPriceBX96 - sqrtPriceAX96));
    }
}
