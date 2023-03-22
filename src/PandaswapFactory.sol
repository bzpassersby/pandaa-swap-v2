//SPDX-License-Identifier:MIT

pragma solidity ^0.8.13;

import "./interfaces/IPandaswapPoolDeployer.sol";
import "./PandaswapPool.sol";

contract PandaswapFactory is IPandaswapPoolDeployer {
    mapping(uint24 => bool) public tickSpacings;
    mapping(address => mapping(address => mapping(uint24 => address)))
        public pools;
    PoolParameters public parameters;
    event PoolCreated(
        address indexed token0,
        address indexed token1,
        uint24 indexed tickSpacing,
        address pool
    );

    error TokensMustBeDifferent();
    error UnsupportedTickSpacing();
    error ZeroAddressNotAllowed();
    error PoolAlreadyExists();

    constructor() {
        tickSpacings[10] = true;
        tickSpacings[60] = true;
    }

    function createPool(
        address tokenX,
        address tokenY,
        uint24 tickSpacing
    ) public returns (address pool) {
        if (tokenX == tokenY) revert TokensMustBeDifferent();
        if (!tickSpacings[tickSpacing]) revert UnsupportedTickSpacing();
        (tokenX, tokenY) = tokenX < tokenY
            ? (tokenX, tokenY)
            : (tokenY, tokenX);
        if (tokenX == address(0) || tokenY == address(0))
            revert ZeroAddressNotAllowed();
        if (pools[tokenX][tokenY][tickSpacing] != address(0))
            revert PoolAlreadyExists();
        parameters = PoolParameters({
            factory: address(this),
            token0: tokenX,
            token1: tokenY,
            tickSpacing: tickSpacing
        });
        pool = address(
            new PandaswapPool{
                salt: keccak256(abi.encodePacked(tokenX, tokenY, tickSpacing))
            }()
        );
        delete parameters;
        pools[tokenX][tokenY][tickSpacing] = pool;
        pools[tokenY][tokenX][tickSpacing] = pool;
        emit PoolCreated(tokenX, tokenY, tickSpacing, pool);
    }
}
