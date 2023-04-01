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
        //fee growth on the other side of this tick (relative to the current tick)
        uint256 feeGrowthOutside0X128;
        uint256 feeGrowthOutside1X128;
    }

    function update(
        mapping(int24 => Info) storage self,
        int24 tick,
        int128 liquidityDelta,
        int24 currentTick,
        uint256 feeGrowthGlobal0X128,
        uint256 feeGrowthGlobal1X128,
        bool upper
    ) internal returns (bool flipped) {
        Info storage tickInfo = self[tick];
        uint128 liquidityBefore = tickInfo.liquidityGross;
        if (liquidityBefore == 0) {
            //by convention, assume that all previous fees were collected below
            //the tick
            if (tick <= currentTick) {
                tickInfo.feeGrowthOutside0X128 = feeGrowthGlobal0X128;
                tickInfo.feeGrowthOutside1X128 = feeGrowthGlobal1X128;
            }
            tickInfo.initialized = true;
        }
        uint128 liquidityAfter = LiquidityMath.addLiquidity(
            liquidityBefore,
            liquidityDelta
        );
        tickInfo.liquidityGross = liquidityAfter;
        tickInfo.liquidityNet = upper
            ? (tickInfo.liquidityNet - liquidityDelta)
            : (tickInfo.liquidityNet + liquidityDelta);

        flipped = (liquidityAfter == 0) != (liquidityBefore == 0);
    }

    function cross(
        mapping(int24 => Info) storage self,
        int24 tick
    ) internal view returns (int128 liquidityDelta) {
        Info storage tickInfo = self[tick];
        liquidityDelta = tickInfo.liquidityNet;
    }

    function getFeeGrowthInside(
        mapping(int24 => Tick.Info) storage self,
        int24 _lowerTick,
        int24 _upperTick,
        int24 currentTick,
        uint256 feeGrowthGlobal0X128,
        uint256 feeGrowthGlobal1X128
    )
        internal
        view
        returns (uint256 feeGrowthInside0x128, uint256 feeGrowthInside1x128)
    {
        Tick.Info storage lowerTick = self[_lowerTick];
        Tick.Info storage upperTick = self[_upperTick];
        uint256 feeGrowthBelow0X128;
        uint256 feeGrowthBelow1X128;
        if (currentTick >= _lowerTick) {
            feeGrowthBelow0X128 = lowerTick.feeGrowthOutside0X128;
            feeGrowthBelow1X128 = lowerTick.feeGrowthOutside1X128;
        } else {
            feeGrowthBelow0X128 =
                feeGrowthGlobal0X128 -
                lowerTick.feeGrowthOutside0X128;
            feeGrowthBelow1X128 =
                feeGrowthGlobal1X128 -
                lowerTick.feeGrowthOutside1X128;
        }
        uint256 feeGrowthAbove0X128;
        uint256 feeGrowthAbove1X128;
        if (currentTick < _upperTick) {
            feeGrowthAbove0X128 = upperTick.feeGrowthOutside0X128;
            feeGrowthAbove1X128 = upperTick.feeGrowthOutside1X128;
        } else {
            feeGrowthAbove0X128 =
                feeGrowthGlobal0X128 -
                upperTick.feeGrowthOutside0X128;
            feeGrowthAbove1X128 =
                feeGrowthGlobal1X128 -
                upperTick.feeGrowthOutside1X128;
        }
        feeGrowthInside0x128 =
            feeGrowthGlobal0X128 -
            feeGrowthBelow0X128 -
            feeGrowthAbove0X128;
        feeGrowthInside1x128 =
            feeGrowthGlobal1X128 -
            feeGrowthBelow1X128 -
            feeGrowthAbove1X128;
    }
}
