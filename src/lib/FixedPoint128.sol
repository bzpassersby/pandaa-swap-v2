//SPDX-License-Identifier:MIT
pragma solidity ^0.8.13;

library FixedPoint128 {
    uint8 internal constant RESOLUTION = 128;
    uint256 internal constant Q128 = 2 ** 128;
}
