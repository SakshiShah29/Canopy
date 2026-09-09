// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console2} from "forge-std/Test.sol";

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

import {IV4Router} from "v4-periphery/src/interfaces/IV4Router.sol";
import {Actions} from "v4-periphery/src/libraries/Actions.sol";

/// @notice Reference encodings for the Universal Router and PositionManager plans that
///         `frontend/lib/canopy.ts` builds in TypeScript.
///
/// @dev A mis-encoded plan is the worst failure mode available to us: it passes a type check, it
///      passes a dry run against a node that does not simulate the hook, and it reverts inside the
///      router with no reason string. `script/SeedAndSwap.s.sol` is the only version of this
///      encoding that a live Sepolia transaction has ever accepted, so these constants are lifted
///      from it verbatim, and `frontend/scripts/check-encoding.ts` asserts the TypeScript produces
///      the same bytes.
///
///      Run `forge test --match-path test/PlanEncoding.t.sol -vv` to print them.
contract PlanEncodingTest is Test {
    // Fixed inputs, shared with the TypeScript side. Values are arbitrary but must match exactly.
    address internal constant ADAPTER = 0x83b0f98b15c8cDFDbf2C172FD141226f97C649d9;
    address internal constant HOOKS = 0x51247E2291d290d17C08813A175AC86465EdE8c0;
    address internal constant RECIPIENT = 0xcE1606F346726d8714985b680B84dD6959fb4186;
    uint24 internal constant FEE = 3000;
    int24 internal constant TICK_SPACING = 60;
    int24 internal constant TICK_LOWER = -887220;
    int24 internal constant TICK_UPPER = 887220;

    uint128 internal constant AMOUNT_IN = 0.001 ether;
    uint128 internal constant MIN_OUT = 0;
    uint256 internal constant LIQUIDITY = 1_234_567_890;
    uint256 internal constant TOKEN_ID = 42;

    function _poolKey() internal pure returns (PoolKey memory) {
        return PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(ADAPTER),
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(HOOKS)
        });
    }

    /// @dev Writes the fixture rather than printing it. Transcribing 500-byte hex strings by hand
    ///      into the TypeScript is its own source of false failures — the first attempt at this
    ///      spliced two words together and reported a mismatch that did not exist.
    function test_writePlanFixture() public {
        string memory json = string.concat(
            '{\n  "swap": "',
            vm.toString(_swapPlan()),
            '",\n  "mint": "',
            vm.toString(_mintPlan()),
            '",\n  "burn": "',
            vm.toString(_burnPlan()),
            '"\n}\n'
        );

        vm.writeFile("./test/fixtures/plan-encodings.json", json);

        console2.log("wrote test/fixtures/plan-encodings.json");
    }

    function _swapPlan() internal pure returns (bytes memory) {
        PoolKey memory poolKey = _poolKey();

        bytes memory actions =
            abi.encodePacked(uint8(Actions.SWAP_EXACT_IN_SINGLE), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL));

        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: poolKey,
                zeroForOne: true,
                amountIn: AMOUNT_IN,
                amountOutMinimum: MIN_OUT,
                minHopPriceX36: 0,
                hookData: bytes("")
            })
        );
        params[1] = abi.encode(poolKey.currency0, type(uint256).max);
        params[2] = abi.encode(poolKey.currency1, uint256(MIN_OUT));

        return abi.encode(actions, params);
    }

    function _mintPlan() internal pure returns (bytes memory) {
        PoolKey memory poolKey = _poolKey();

        bytes memory actions = abi.encodePacked(uint8(Actions.MINT_POSITION), uint8(Actions.SETTLE_PAIR));

        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(
            poolKey, TICK_LOWER, TICK_UPPER, LIQUIDITY, type(uint128).max, type(uint128).max, RECIPIENT, bytes("")
        );
        params[1] = abi.encode(poolKey.currency0, poolKey.currency1);

        return abi.encode(actions, params);
    }

    function _burnPlan() internal pure returns (bytes memory) {
        PoolKey memory poolKey = _poolKey();

        bytes memory actions = abi.encodePacked(uint8(Actions.BURN_POSITION), uint8(Actions.TAKE_PAIR));

        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(TOKEN_ID, uint128(0), uint128(0), bytes(""));
        params[1] = abi.encode(poolKey.currency0, poolKey.currency1, RECIPIENT);

        return abi.encode(actions, params);
    }
}
