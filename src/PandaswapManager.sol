//SPDX-License-Identifier:MIT

pragma solidity ^0.8.0;

import "./PandaswapPool.sol";

contract PandaswapManager {
    function mint(
        address _poolAddress,
        int24 lowerTick,
        int24 upperTick,
        uint128 liquidity,
        bytes calldata data
    ) public {
        PandaswapPool(_poolAddress).mint(
            msg.sender,
            lowerTick,
            upperTick,
            liquidity,
            data
        );
    }

    function swap(address _poolAddress,bool zeroForOne,uint256 amountSpecified,bytes calldata data) public {
        PandaswapPool(_poolAddress).swap(msg.sender,zeroForOne,amountSpecified,data);
    }

    function pandaswapSwapCallback(
        int256 amount0,
        int256 amount1,
        bytes calldata data
    ) public {
        PandaswapPool.CallbackData memory extra = abi.decode(
            data,
            (PandaswapPool.CallbackData)
        );
        if (amount0 > 0) {
            IERC20(extra.token0).transferFrom(
                extra.payer,
                msg.sender,
                uint256(amount0)
            );
        }
        if (amount1 > 0) {
            IERC20(extra.token1).transferFrom(
                extra.payer,
                msg.sender,
                uint256(amount1)
            );
        }
    }

    function pandaswapMintCallback(
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) public {
        PandaswapPool.CallbackData memory extra = abi.decode(
            data,
            (PandaswapPool.CallbackData)
        );
        IERC20(extra.token0).transferFrom(extra.payer, msg.sender, amount0);
        IERC20(extra.token1).transferFrom(extra.payer, msg.sender, amount1);
    }
}
