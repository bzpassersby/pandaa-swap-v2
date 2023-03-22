//SPDX-License-Identifier:MIT

pragma solidity ^0.8.14;

import "lib/abdk-libraries-solidity/ABDKMath64x64.sol";
import "../src/lib/FixedPoint96.sol";
import "../src/lib/TickMath.sol";
import "forge-std/Test.sol";
import "../src/PandaswapPool.sol";
import "./ERC20Mintable.sol";
import "../src/interfaces/IPandaswapManager.sol";
import "../src/PandaswapManager.sol";

abstract contract TestUtils is Test {
    struct ExpectedStateAfterMint {
        PandaswapPool pool;
        ERC20Mintable token0;
        ERC20Mintable token1;
        uint256 amount0;
        uint256 amount1;
        int24 lowerTick;
        int24 upperTick;
        uint128 positionLiquidity;
        uint128 currentLiquidity;
        uint160 sqrtPriceX96;
        int24 tick;
    }

    struct ExpectedStateAfterSwap {
        PandaswapPool pool;
        ERC20Mintable token0;
        ERC20Mintable token1;
        uint256 userBalance0;
        uint256 userBalance1;
        uint256 poolBalance0;
        uint256 poolBalance1;
        uint160 sqrtPriceX96;
        int24 tick;
        uint128 currentLiquidity;
    }

    function tick(uint256 price) internal pure returns (int24 _tick) {
        _tick = TickMath.getTickAtSqrtRatio(
            uint160(
                int160(
                    ABDKMath64x64.sqrt(int128(int256(price << 64))) <<
                        (FixedPoint96.RESOLUTION - 64)
                )
            )
        );
    }

    function tick60(uint256 price) internal pure returns (int24 _tick) {
        _tick = tick(price);
        _tick = nearestUsableTick(_tick, 60);
    }

    function sqrtP(uint256 price) internal pure returns (uint160 _sqrtPrice) {
        _sqrtPrice = uint160(
            int160(
                ABDKMath64x64.sqrt(int128(int256(price << 64))) <<
                    (FixedPoint96.RESOLUTION - 64)
            )
        );
    }

    function sqrtP60FromTick(int24 _tick) internal pure returns (uint160) {
        return TickMath.getSqrtRatioAtTick(nearestUsableTick(_tick, 60));
    }

    function tickInBitMap(
        PandaswapPool pool,
        int24 _tick
    ) internal view returns (bool initialized) {
        int16 wordPos = int16(_tick >> 8);
        uint8 bitPos = uint8(uint24(_tick % 256));
        uint256 word = pool.tickBitmap(wordPos);
        initialized = (word & (1 << bitPos)) != 0;
    }

    function assertMintState(ExpectedStateAfterMint memory expected) internal {
        //check token balance in pool
        assertEq(
            expected.token0.balanceOf(address(expected.pool)),
            expected.amount0,
            "incorrect token0 balance of pool"
        );
        assertEq(
            expected.token1.balanceOf(address(expected.pool)),
            expected.amount1,
            "incorrect token1 balance of pool"
        );
        //check user minted liquidity position
        bytes32 positionKey = keccak256(
            abi.encodePacked(
                address(this),
                expected.lowerTick,
                expected.upperTick
            )
        );
        uint128 posLiquidity = expected.pool.positions(positionKey);
        assertEq(
            posLiquidity,
            expected.positionLiquidity,
            "incorrect position liquidity"
        );
        // check status of lower and upper tick
        (
            bool tickInitialized,
            uint128 tickLiquidityGross,
            int128 tickLiquidityNet
        ) = expected.pool.ticks(expected.lowerTick);
        assertTrue(tickInitialized);
        assertEq(
            tickLiquidityGross,
            expected.positionLiquidity,
            "incorrect lower tick gross liquidity"
        );
        assertEq(
            tickLiquidityNet,
            int128(expected.positionLiquidity),
            "incorrect lower tick net liquidity"
        );
        // check tick bitmap status of lower and upper tick
        assertTrue(tickInBitMap(expected.pool, expected.lowerTick));
        assertTrue(tickInBitMap(expected.pool, expected.upperTick));
        // check current price and tick didn't change in pool
        (uint160 sqrtPriceX96, int24 currentTick) = expected.pool.slot0();
        assertEq(sqrtPriceX96, expected.sqrtPriceX96, "invalid current sqrtP");
        assertEq(currentTick, expected.tick, "invalid current tick");
        // check current liquidity in pool is updated
        assertEq(
            expected.pool.liquidity(),
            expected.currentLiquidity,
            "invalid current liquidity"
        );
    }

    function assertSwapState(ExpectedStateAfterSwap memory expected) internal {
        assertEq(
            expected.token0.balanceOf(address(this)),
            uint256(expected.userBalance0),
            "invalid user ETH balance"
        );
        assertEq(
            expected.token1.balanceOf(address(this)),
            uint256(expected.userBalance1),
            "invalid user USDC balance"
        );
        assertEq(
            expected.token0.balanceOf(address(expected.pool)),
            uint256(expected.poolBalance0),
            "invalid pool ETH balance"
        );
        assertEq(
            expected.token1.balanceOf(address(expected.pool)),
            uint256(expected.poolBalance1),
            "invalid pool USDC balance"
        );
        (uint160 sqrtPriceX96, int24 currentTick) = expected.pool.slot0();
        assertEq(sqrtPriceX96, expected.sqrtPriceX96, "invalid current sqrtP");
        assertEq(currentTick, expected.tick, "invalid current tick");
        assertEq(
            expected.pool.liquidity(),
            expected.currentLiquidity,
            "invalid current liquidity"
        );
    }

    function divRound(
        int128 x,
        int128 y
    ) internal pure returns (int128 result) {
        int128 quot = ABDKMath64x64.div(x, y);
        result = quot >> 64;
        // Check if remainder is greater than 0.5
        if (x >= 0) {
            if (quot % 2 ** 64 >= 0x8000000000000000) {
                result += 1;
            }
        } else {
            if (quot % 2 ** 64 >= 0x8000000000000000) {
                result -= 1;
            }
        }
    }

    function nearestUsableTick(
        int24 _tick,
        uint24 tickSpacing
    ) internal pure returns (int24 result) {
        result =
            int24(divRound(int128(_tick), int128(int24(tickSpacing)))) *
            int24(tickSpacing);

        if (result < TickMath.MIN_TICK) {
            result += int24(tickSpacing);
        } else if (result > TickMath.MAX_TICK) {
            result -= int24(tickSpacing);
        }
    }

    function mintParams60(
        address tokenA,
        address tokenB,
        uint256 lowerPrice,
        uint256 upperPrice,
        uint256 amount0,
        uint256 amount1
    ) internal pure returns (PandaswapManager.MintParams memory params) {
        params = PandaswapManager.MintParams({
            tokenA: tokenA,
            tokenB: tokenB,
            tickSpacing: 60,
            lowerTick: tick60(lowerPrice),
            upperTick: tick60(upperPrice),
            amount0Desired: amount0,
            amount1Desired: amount1,
            amount0Min: 0,
            amount1Min: 0
        });
    }

    function encodeError(
        string memory error
    ) internal pure returns (bytes memory encoded) {
        encoded = abi.encodeWithSignature(error);
    }

    function encodeExtra(
        address _token0,
        address _token1,
        address _payer
    ) internal pure returns (bytes memory) {
        return
            abi.encode(
                IPandaswapManager.CallbackData({
                    token0: _token0,
                    token1: _token1,
                    payer: _payer
                })
            );
    }
}
