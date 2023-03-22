//SPDX-License-Identifier:MIT

pragma solidity ^0.8.0;

/// @title Callback for PandaswapPool.sol #mint
/// @notice Any contract that calls IPandaswapPool#mint must implement this interface

interface IPandaswapMintCallback {
    function pandaswapMintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata data
    ) external;
}
