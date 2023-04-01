//SPDX-License-Identifier:MIT

pragma solidity ^0.8.13;

import "./interfaces/IPandaswapPoolDeployer.sol";
import "./PandaswapPool.sol";

contract PandaswapFactory is IPandaswapPoolDeployer {
    mapping(uint24 => uint24) public fees;

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
    error UnsupportedFee();
    error ZeroAddressNotAllowed();
    error PoolAlreadyExists();

    constructor() {
        fees[500] = 10;
        fees[3000] = 60;
    }

    function createPool(
        address tokenX,
        address tokenY,
        uint24 fee
    ) public returns (address pool) {
        if (tokenX == tokenY) revert TokensMustBeDifferent();
        if (fees[fee] == 0) revert UnsupportedFee();
        (tokenX, tokenY) = tokenX < tokenY
            ? (tokenX, tokenY)
            : (tokenY, tokenX);
        if (tokenX == address(0) || tokenY == address(0))
            revert ZeroAddressNotAllowed();
        if (pools[tokenX][tokenY][fee] != address(0))
            revert PoolAlreadyExists();
        parameters = PoolParameters({
            factory: address(this),
            token0: tokenX,
            token1: tokenY,
            tickSpacing: fees[fee],
            fee: fee
        });
        pool = address(
            new PandaswapPool{
                salt: keccak256(abi.encodePacked(tokenX, tokenY, fee))
            }()
        );
        delete parameters;
        pools[tokenX][tokenY][fee] = pool;
        pools[tokenY][tokenX][fee] = pool;
        emit PoolCreated(tokenX, tokenY, fee, pool);
    }
}
