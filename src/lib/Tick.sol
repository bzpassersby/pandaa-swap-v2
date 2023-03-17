//SPDX-License-Identifier:MIT

import "./LiquidityMath.sol";

pragma solidity ^0.8.0;

library Tick {
    struct Info {
        bool initialized;
        // total liquidity at tick
        uint128 liquidityGross;
        // amount of liquidity added or subtraced when tick is crossed
        int128 liquidityNet;
    }

    function update(
        mapping(int24 => Info) storage self,
        int24 tick,
        int128 liquidityDelta,
        bool upper
    ) internal returns (bool flipped) {
        Info storage tickInfo = self[tick];
        uint128 liquidityBefore = tickInfo.liquidityGross;
        uint128 liquidityAfter = LiquidityMath.addLiquidity(
            liquidityBefore,
            liquidityDelta
        );
        tickInfo.liquidityGross = liquidityAfter;
        tickInfo.liquidityNet = upper
            ? (tickInfo.liquidityNet - liquidityDelta)
            : (tickInfo.liquidityNet + liquidityDelta);
        if (liquidityBefore == 0) {
            tickInfo.initialized = true;
        }
        flipped = (liquidityAfter == 0) != (liquidityBefore == 0);
    }

    function cross(
        mapping(int24 => Info) storage self,
        int24 tick
    ) internal view returns (int128 liquidityDelta) {
        Info storage tickInfo = self[tick];
        liquidityDelta = tickInfo.liquidityNet;
    }
}
