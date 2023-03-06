//SPDX-License-Identifier:MIT

pragma solidity ^0.8.0;

library Tick {
    struct Info {
        bool initialized;
        uint128 liquidity;
    }

    function update(
        mapping(int24 => Info) storage self,
        int24 tick,
        uint128 liquidityDelta
    ) internal {
        Info storage tickInfo = self[tick];
        uint128 liquidityBefore = tickInfo.liquidity;
        uint128 liquidityAfter = liquidityBefore + liquidityDelta;
        if (liquidityBefore == 0) {
            self[tick].initialized = true;
        }
        self[tick].liquidity = liquidityAfter;
    }
}
