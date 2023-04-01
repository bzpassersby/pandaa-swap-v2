//SPDX-License-Identifier:MIT
pragma solidity ^0.8.14;

import "forge-std/Test.sol";
import "./TestUtils.sol";
import "./ERC20Mintable.sol";
import "../src/PandaswapFactory.sol";

contract PandaswapFactoryTest is Test, TestUtils {
    ERC20Mintable weth;
    ERC20Mintable usdc;
    PandaswapFactory factory;

    function setUp() public {
        usdc = new ERC20Mintable("USDC", "USDC", 18);
        weth = new ERC20Mintable("Eth", "Weth", 18);
        factory = new PandaswapFactory();
    }

    //Success case
    function testCreatePool() public {
        address poolAddress = factory.createPool(
            address(weth),
            address(usdc),
            500
        );
        PandaswapPool pool = PandaswapPool(poolAddress);
        //verify poolAddress state is updated
        assertEq(
            factory.pools(address(weth), address(usdc), 500),
            poolAddress,
            "invalid pool address in the registry"
        );
        assertEq(
            factory.pools(address(usdc), address(weth), 500),
            poolAddress,
            "invalid pool address in the registry(reverse order)"
        );
        //verify pool contract stores correct factory address
        assertEq(pool.factory(), address(factory), "invalid factory address");
        //verify pool contract stores correct token address and tickSpacing
        assertEq(pool.token0(), address(weth), "invalid token0 address");
        assertEq(pool.token1(), address(usdc), "invalid token1 address");
        assertEq(pool.tickSpacing(), 10, "invalid tick spacing");
        //verify pool contract stores correct sqrtPrice and tick
        (uint160 sqrtPriceX96, int24 tick, , , ) = pool.slot0();
        assertEq(sqrtPriceX96, 0, "invalid sqrtPriceX96");
        assertEq(tick, 0, "invalid current tick");
    }

    //Failure case
    function testCreatePoolIdenticalTokens() public {
        vm.expectRevert(encodeError("TokensMustBeDifferent()"));
        factory.createPool(address(weth), address(weth), 500);
    }

    function testCreateZeroTokenAddress() public {
        vm.expectRevert(encodeError("ZeroAddressNotAllowed()"));
        factory.createPool(address(weth), address(0), 500);
    }

    function testCreateAlreadyExists() public {
        factory.createPool(address(weth), address(usdc), 500);
        vm.expectRevert(encodeError("PoolAlreadyExists()"));
        factory.createPool(address(weth), address(usdc), 500);
    }
}
