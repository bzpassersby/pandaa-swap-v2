// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../src/PandaswapPool.sol";
import "forge-std/Test.sol";
import "./ERC20Mintable.sol";

contract PandaswapPoolTest is Test {
    ERC20Mintable token0;
    ERC20Mintable token1;
    PandaswapPool pool;

    struct TestCaseParams {
        uint256 wethBalance;
        uint256 usdcBalance;
        int24 currentTick;
        int24 lowerTick;
        int24 upperTick;
        uint128 liquidity;
        uint160 currentSqrtP;
        bool shouldTransferInCallback;
        bool mintLiquidity;
    }
    bool shouldTransferInCallback;

    function setUp() public {
        console.log("deploying...");
        token0 = new ERC20Mintable("Wrapped Ether", "WETH", 18);
        token1 = new ERC20Mintable("USDC", "USDC", 18);
        console.log(address(token0), address(token1));
    }

    function testMintSuccess() public {
        //set up pool params
        TestCaseParams memory params = TestCaseParams({
            wethBalance: 1 ether,
            usdcBalance: 5001 ether,
            currentTick: 85176,
            lowerTick: 84222,
            upperTick: 86129,
            liquidity: 1517882343751509868544,
            currentSqrtP: 5602277097478614198912276234240,
            shouldTransferInCallback: true,
            mintLiquidity: true
        });

        //deploy pool and mint position
        (uint256 poolBalance0, uint256 poolBalance1) = setupTestCase(params);
        //assert amount deposited
        assertEq(token0.balanceOf(address(pool)), poolBalance0);
        assertEq(token1.balanceOf(address(pool)), poolBalance1);
        //assert position created
        bytes32 positionKey = keccak256(
            abi.encodePacked(address(this), params.lowerTick, params.upperTick)
        );
        uint128 posLiquidity = pool.positions(positionKey);
        assertEq(posLiquidity, params.liquidity);
        //asert tick initialized
        (bool tickInitialized, uint128 tickLiquidity) = pool.ticks(
            params.lowerTick
        );
        assertTrue(tickInitialized);
        assertEq(
            tickLiquidity,
            params.liquidity,
            "lowerTick liquidity not satisfied"
        );
        (tickInitialized, tickLiquidity) = pool.ticks(params.upperTick);
        assertTrue(tickInitialized);
        assertEq(
            tickLiquidity,
            params.liquidity,
            "upperTick liquidity not satisfied"
        );
        //assert current token price and L
        (uint160 sqrtPriceX96, int24 tick) = pool.slot0();
        assertEq(
            sqrtPriceX96,
            5602277097478614198912276234240,
            "invalid current sqrtP"
        );
        assertEq(tick, 85176, "invalid current tick");
        assertEq(
            pool.liquidity(),
            1517882343751509868544,
            "invalid current liquidity"
        );
    }

    function setupTestCase(
        TestCaseParams memory params
    ) internal returns (uint256 poolBalance0, uint256 poolBalance1) {
        token0.mint(address(this), params.wethBalance);
        token1.mint(address(this), params.usdcBalance);
        pool = new PandaswapPool(
            address(token0),
            address(token1),
            params.currentSqrtP,
            params.currentTick
        );
        shouldTransferInCallback = params.shouldTransferInCallback;
        //set up callback params
        PandaswapPool.CallbackData memory extra = PandaswapPool.CallbackData({
            token0: address(token0),
            token1: address(token1),
            payer: address(this)
        });
        bytes memory data = abi.encode(extra);

        if (params.mintLiquidity) {
            console.log("minting position...");
            (poolBalance0, poolBalance1) = pool.mint(
                address(this),
                params.lowerTick,
                params.upperTick,
                params.liquidity,
                data
            );
        }
    }

    function pandaswapMintCallback(
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) public {
        if (shouldTransferInCallback) {
            PandaswapPool.CallbackData memory extra = abi.decode(
                data,
                (PandaswapPool.CallbackData)
            );
            IERC20(extra.token0).transfer(msg.sender, amount0);
            IERC20(extra.token1).transfer(msg.sender, amount1);
        }
        console.log(amount0, amount1);
    }

    function testSwapBuyEth() public {
        //pool params
        TestCaseParams memory params = TestCaseParams({
            wethBalance: 1 ether,
            usdcBalance: 5001 ether,
            currentTick: 85176,
            lowerTick: 84222,
            upperTick: 86129,
            liquidity: 1517882343751509868544,
            currentSqrtP: 5602277097478614198912276234240,
            shouldTransferInCallback: true,
            mintLiquidity: true
        });
        //callback params
        PandaswapPool.CallbackData memory extra = PandaswapPool.CallbackData({
            token0: address(token0),
            token1: address(token1),
            payer: address(this)
        });
        bytes memory data = abi.encode(extra);
        //deploy pool and mint initial liquidity position
        (uint256 poolBalance0, uint256 poolBalance1) = setupTestCase(params);
        //send user token to swap
        token1.mint(address(this), 42 ether);
        int256 userBalance0Before = int256(token0.balanceOf(address(this)));
        int256 userBalance1Before=int256(token1.balanceOf(address(this)));
        //user swap
        (int256 amount0Delta, int256 amount1Delta) = pool.swap(
            address(this),
            false,
            42 ether,
            data
        );
        //check swap amount0, amount1 output
        assertEq(amount0Delta, -0.008396714242162445 ether, "invalid ETH out");
        assertEq(amount1Delta, 42 ether, "invalid USDC in");
        //verify user balance after
        assertEq(
            token0.balanceOf(address(this)),
            uint256(userBalance0Before - amount0Delta),
            "invalid user ETH balance"
        );
        assertEq(
            token1.balanceOf(address(this)),
            uint256(userBalance1Before - amount1Delta),
            "invalid user USDC balance"
        );
        //verify pool balance
        assertEq(
            uint256(int256(poolBalance0) + amount0Delta),
            token0.balanceOf(address(pool)),
            "invalid pool Eth balance"
        );
        assertEq(
            uint256(int256(poolBalance1) + amount1Delta),
            token1.balanceOf(address(pool)),
            "invalid pool USDC balance"
        );
        //verify pool state changes
        (uint160 sqrtPriceX96, int24 tick) = pool.slot0();
        assertEq(
            sqrtPriceX96,
            5604469350942327889444743441197,
            "invalid current sqrtP"
        );
        assertEq(tick, 85184, "invalid current tick");
        assertEq(
            pool.liquidity(),
            1517882343751509868544,
            "invalid current liquidity"
        );
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
            IERC20(extra.token0).transfer(msg.sender, uint256(amount0));
        }
        if (amount1 > 0) {
            IERC20(extra.token1).transfer(msg.sender, uint256(amount1));
        }
    }
}
