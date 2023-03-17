//SPDX-License-Identifier:MIT

pragma solidity ^0.8.14;

import "lib/abdk-libraries-solidity/ABDKMath64x64.sol";
import "../src/lib/FixedPoint96.sol";
import "../src/lib/TickMath.sol";
import "forge-std/Test.sol";
import "../src/PandaswapPool.sol";
import "./ERC20Mintable.sol";

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

    function sqrtP(uint256 price) internal pure returns (uint160 _sqrtPrice) {
        _sqrtPrice = uint160(
            int160(
                ABDKMath64x64.sqrt(int128(int256(price << 64))) <<
                    (FixedPoint96.RESOLUTION - 64)
            )
        );
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

    function encodeError(
        string memory error
    ) internal pure returns (bytes memory encoded) {
        encoded = abi.encodeWithSignature(error);
    }

    function encodeExtra(
        address _token0,
        address _token1,
        address _prayer
    ) internal pure returns (bytes memory) {
        return
            abi.encode(
                PandaswapPool.CallbackData({
                    token0: _token0,
                    token1: _token1,
                    payer: _prayer
                })
            );
    }
}
