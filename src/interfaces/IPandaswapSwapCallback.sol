//SPDX-License-Identifier:MIT

pragma solidity ^0.8.0;

/// @title Callback for PandaswapPool.sol #mint
/// @notice Any contract that calls IPandaswapPool#mint must implement this interface

interface IPandaswapSwapCallback {
    function pandaswapSwapCallback(
        int256 amount0,
        int256 amount1,
        bytes calldata data
    ) external;
}
