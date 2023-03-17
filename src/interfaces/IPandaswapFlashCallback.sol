//SPDX-License-Identifier:MIT

pragma solidity ^0.8.0;

/// @title Callback for PandaswapPool.sol #flash
/// @notice Any contract that calls IPandaswapPool#flash must implement this interface

interface IPandaswapFlashCallback {
    function pandaswapFlashCallback(bytes calldata data) external;
}
