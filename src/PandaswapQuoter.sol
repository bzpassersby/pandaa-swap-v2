//SPDX-License-Identifier:MIT

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "./PandaswapPool.sol";
import "./lib/PoolAddress.sol";
import "./lib/TickMath.sol";
import "./lib/Path.sol";

contract PandaswapQuoter is Test {
    using Path for bytes;
    struct QuoteSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 tickSpacing;
        uint256 amountIn;
        uint160 sqrtPriceLimitX96;
    }

    address public immutable factory;

    constructor(address _factory) {
        factory = _factory;
    }

    function quoteSingle(
        QuoteSingleParams memory params
    )
        public
        returns (uint256 amountOut, uint160 sqrtPriceX96After, int24 tickAfter)
    {
        PandaswapPool pool = getPool(
            params.tokenIn,
            params.tokenOut,
            params.tickSpacing
        );
        bool zeroForOne = params.tokenIn < params.tokenOut;
        try
            pool.swap(
                address(this),
                zeroForOne,
                params.amountIn,
                params.sqrtPriceLimitX96 == 0
                    ? (
                        zeroForOne
                            ? TickMath.MIN_SQRT_RATIO + 1
                            : TickMath.MAX_SQRT_RATIO - 1
                    )
                    : params.sqrtPriceLimitX96,
                abi.encode(address(pool))
            )
        {} catch (bytes memory reason) {
            (amountOut, sqrtPriceX96After, tickAfter) = abi.decode(
                reason,
                (uint256, uint160, int24)
            );
        }
    }

    function quote(
        bytes memory path,
        uint256 amountIn
    )
        public
        returns (
            uint256 amountOut,
            uint160[] memory sqrtPriceX96AfterList,
            int24[] memory tickAfterList
        )
    {
        sqrtPriceX96AfterList = new uint160[](path.numPools());
        tickAfterList = new int24[](path.numPools());
        uint256 i = 0;
        while (true) {
            (address tokenIn, address tokenOut, uint24 tickSpacing) = path
                .decodeFirstPool();
            (
                uint256 _amountOut,
                uint160 sqrtPriceX96,
                int24 tickAfter
            ) = quoteSingle(
                    QuoteSingleParams({
                        tokenIn: tokenIn,
                        tokenOut: tokenOut,
                        tickSpacing: tickSpacing,
                        amountIn: amountIn,
                        sqrtPriceLimitX96: 0
                    })
                );
            sqrtPriceX96AfterList[i] = sqrtPriceX96;
            tickAfterList[i] = tickAfter;
            amountIn = _amountOut;
            i++;

            if (path.hasMultiplePools()) {
                path = path.skipToken();
            } else {
                amountOut = amountIn;
                break;
            }
        }
    }

    function pandaswapSwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes memory data
    ) external view {
        address pool = abi.decode(data, (address));

        uint256 amountOut = amount0Delta > 0
            ? uint256(-amount1Delta)
            : uint256(-amount0Delta);
        (uint160 sqrtPriceX96After, int24 tickAfter, , , ) = PandaswapPool(pool)
            .slot0();

        assembly {
            let ptr := mload(0x40)
            mstore(ptr, amountOut)
            mstore(add(ptr, 0x20), sqrtPriceX96After)
            mstore(add(ptr, 0x40), tickAfter)
            revert(ptr, 96)
        }
    }

    function getPool(
        address token0,
        address token1,
        uint24 tickSpacing
    ) internal view returns (PandaswapPool pool) {
        (token0, token1) = token0 < token1
            ? (token0, token1)
            : (token1, token0);
        pool = PandaswapPool(
            PoolAddress.computeAddress(factory, token0, token1, tickSpacing)
        );
    }
}
