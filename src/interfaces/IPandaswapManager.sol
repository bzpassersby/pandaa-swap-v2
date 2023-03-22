//SPDX-License-Identifier:MIT

pragma solidity ^0.8.13;

interface IPandaswapManager {
    struct SwapCallbackData {
        bytes path;
        address payer;
    }

    struct CallbackData {
        address token0;
        address token1;
        address payer;
    }
}
