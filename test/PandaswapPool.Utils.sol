//SPDX-License-Identifier: MIT

pragma solidity ^0.8.14;

import "../src/lib/LiquidityMath.sol";
import "./TestUtils.sol";

abstract contract PandaswapPoolUtils is TestUtils {
    struct LiquidityRange {
        int24 lowerTick;
        int24 upperTick;
        uint128 amount;
    }

    struct TestCaseParams {
        uint256 wethBalance;
        uint256 usdcBalance;
        uint256 currentPrice;
        LiquidityRange[] liquidity;
        bool transferInMintCallback;
        bool transferInSwapCallback;
        bool mintLiquidity;
    }

    function liquidityRange(
        uint256 lowerPrice,
        uint256 upperPrice,
        uint256 amount0,
        uint256 amount1,
        uint256 currentPrice
    ) internal pure returns (LiquidityRange memory range) {
        range = LiquidityRange({
            lowerTick: tick(lowerPrice),
            upperTick: tick(upperPrice),
            amount: LiquidityMath.getLiquidityForAmounts(
                sqrtP(currentPrice),
                sqrtP(lowerPrice),
                sqrtP(upperPrice),
                amount0,
                amount1
            )
        });
    }

    function liquidityRange(
        uint256 lowerPrice,
        uint256 upperPrice,
        uint128 _amount
    ) internal pure returns (LiquidityRange memory range) {
        range = LiquidityRange({
            lowerTick: tick(lowerPrice),
            upperTick: tick(upperPrice),
            amount: _amount
        });
    }
}
