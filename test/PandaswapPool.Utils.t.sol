//SPDX-License-Identifier: MIT

pragma solidity ^0.8.14;

abstract contract PandaswapUtils {
    struct LiquidityRange {
        int24 lowerTick;
        int24 upperTick;
        uint128 amount;
    }
}
