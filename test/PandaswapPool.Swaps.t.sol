//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./TestUtils.sol";
import "../src/PandaswapPool.sol";
import "./ERC20Mintable.sol";
import "./PandaswapPool.Utils.sol";
import "../src/interfaces/IPandaswapManager.sol";
import "../src/lib/Path.sol";
import "../src/interfaces/IPandaswapPoolDeployer.sol";
import "../src/PandaswapFactory.sol";

contract PandaswapPoolSwapsTest is
    Test,
    TestUtils,
    PandaswapPoolUtils,
    IPandaswapPoolDeployer,
    IPandaswapManager
{
    using Path for bytes;
    ERC20Mintable token0;
    ERC20Mintable token1;
    PandaswapPool pool;
    PandaswapFactory factory;
    PoolParameters public parameters;
    bytes extra;
    bool transferInMintCallback = true;
    bool transferInSwapCallback = true;

    function setUp() public {
        token1 = new ERC20Mintable("Ether", "ETH", 18);
        token0 = new ERC20Mintable("USDC", "USDC", 18);
        factory = new PandaswapFactory();
        extra = encodeExtra(address(token0), address(token1), address(this));
    }

    //  One price range
    //
    //          5000
    //  4545 -----|----- 5500
    //
    function testBuyETHOnePriceRange() public {
        LiquidityRange[] memory liquidity = new LiquidityRange[](1);
        liquidity[0] = liquidityRange(4545, 5500, 1 ether, 5000 ether, 5000);
        TestCaseParams memory params = TestCaseParams({
            wethBalance: 1 ether,
            usdcBalance: 5000 ether,
            currentPrice: 5000,
            liquidity: liquidity,
            transferInMintCallback: true,
            transferInSwapCallback: true,
            mintLiquidity: true
        });

        (uint256 poolBalance0, uint256 poolBalance1) = setupTestCase(params);
        uint256 swapAmount = 42 ether;
        token1.mint(address(this), swapAmount);
        token1.approve(address(this), swapAmount);
        (int256 userBalance0Before, int256 userBalance1Before) = (
            int256(token0.balanceOf(address(this))),
            int256(token1.balanceOf(address(this)))
        );
        (int256 amount0Delta, int256 amount1Delta) = pool.swap(
            address(this),
            false,
            swapAmount,
            sqrtP(5005),
            extra
        );
        // check amountIn
        assertEq(amount1Delta, 42 ether, "invalid USDC in");
        assertSwapState(
            ExpectedStateAfterSwap({
                pool: pool,
                token0: token0,
                token1: token1,
                userBalance0: uint256(userBalance0Before - amount0Delta),
                userBalance1: uint256(userBalance1Before - amount1Delta),
                poolBalance0: uint256(int256(poolBalance0) + amount0Delta),
                poolBalance1: uint256(int256(poolBalance1) + amount1Delta),
                sqrtPriceX96: 5604422590555458105735383351329,
                tick: 85183,
                currentLiquidity: liquidity[0].amount
            })
        );
    }

    //  two price range
    //
    //          5000
    //  4545 -----|----- 5500
    //
    function testBuyETHTwoEqualPriceRanges() public {
        LiquidityRange memory range = liquidityRange(
            4545,
            5500,
            1 ether,
            5000 ether,
            5000
        );
        LiquidityRange[] memory liquidity = new LiquidityRange[](2);
        liquidity[0] = range;
        liquidity[1] = range;
        TestCaseParams memory params = TestCaseParams({
            wethBalance: 2 ether,
            usdcBalance: 10000 ether,
            currentPrice: 5000,
            liquidity: liquidity,
            transferInMintCallback: true,
            transferInSwapCallback: true,
            mintLiquidity: true
        });
        (uint256 poolBalance0, uint256 poolBalance1) = setupTestCase(params);
        uint256 swapAmount = 42 ether; //42 USDC
        token1.mint(address(this), swapAmount);
        token1.approve(address(this), swapAmount);
        (int256 userBalance0Before, int256 userBalance1Before) = (
            int256(token0.balanceOf(address(this))),
            int256(token1.balanceOf(address(this)))
        );
        (int256 amount0Delta, int256 amount1Delta) = pool.swap(
            address(this),
            false,
            swapAmount,
            sqrtP(5005),
            extra
        );
        //check valid token1 output amount
        assertEq(amount1Delta, int256(42 ether), "invalid USDC in");
        assertSwapState(
            ExpectedStateAfterSwap({
                pool: pool,
                token0: token0,
                token1: token1,
                userBalance0: uint256(userBalance0Before - amount0Delta),
                userBalance1: uint256(userBalance1Before - amount1Delta),
                poolBalance0: uint256(int256(poolBalance0) + amount0Delta),
                poolBalance1: uint256(int256(poolBalance1) + amount1Delta),
                sqrtPriceX96: 5603349844017036048802233057296,
                tick: 85180,
                currentLiquidity: liquidity[0].amount + liquidity[1].amount
            })
        );
    }

    //  Consecutive price ranges
    //
    //          5000
    //  4545 -----|----- 5500
    //             5500 ----------- 6250
    //
    function testBuyETHConsecutivePriceRanges() public {
        LiquidityRange[] memory liquidity = new LiquidityRange[](2);
        liquidity[0] = liquidityRange(4545, 5500, 1 ether, 5000 ether, 5000);
        liquidity[1] = liquidityRange(5500, 6250, 1 ether, 5000 ether, 5000);
        TestCaseParams memory params = TestCaseParams({
            wethBalance: 2 ether,
            usdcBalance: 10000 ether,
            currentPrice: 5000,
            liquidity: liquidity,
            transferInMintCallback: true,
            transferInSwapCallback: true,
            mintLiquidity: true
        });
        (uint256 poolBalance0, uint256 poolBalance1) = setupTestCase(params);
        uint256 swapAmount = 10000 ether;
        token1.mint(address(this), swapAmount);
        token1.approve(address(this), swapAmount);
        (int256 userBalance0Before, int256 userBalance1Before) = (
            int256(token0.balanceOf(address(this))),
            int256(token1.balanceOf(address(this)))
        );
        (int256 amount0Delta, int256 amount1Delta) = pool.swap(
            address(this),
            false,
            swapAmount,
            sqrtP(6210),
            extra
        );
        //check token1 input amount
        assertEq(amount1Delta, int256(swapAmount), "invalid USDC in");
        assertSwapState(
            ExpectedStateAfterSwap({
                pool: pool,
                token0: token0,
                token1: token1,
                userBalance0: uint256(userBalance0Before - amount0Delta),
                userBalance1: uint256(userBalance1Before - amount1Delta),
                poolBalance0: uint256(int256(poolBalance0) + amount0Delta),
                poolBalance1: uint256(int256(poolBalance1) + amount1Delta),
                sqrtPriceX96: 6113108782441498245750117063186,
                tick: 86921,
                currentLiquidity: liquidity[1].amount
            })
        );
    }

    //  Partially overlapping price ranges
    //
    //          5000
    //  4545 -----|----- 5500
    //      5000+1 ----------- 6250
    //
    function testBuyETHPartiallyOverlappingPriceRanges() public {
        LiquidityRange[] memory liquidity = new LiquidityRange[](2);
        liquidity[0] = liquidityRange(4545, 5500, 1 ether, 5000 ether, 5000);
        liquidity[1] = liquidityRange(5001, 6250, 1 ether, 5000 ether, 5000);
        TestCaseParams memory params = TestCaseParams({
            wethBalance: 2 ether,
            usdcBalance: 10000 ether,
            currentPrice: 5000,
            liquidity: liquidity,
            transferInMintCallback: true,
            transferInSwapCallback: true,
            mintLiquidity: true
        });
        (uint256 poolBalance0, uint256 poolBalance1) = setupTestCase(params);
        uint256 swapAmount = 10000 ether;
        token1.mint(address(this), swapAmount);
        token1.approve(address(this), swapAmount);
        (int256 userBalance0Before, int256 userBalance1Before) = (
            int256(token0.balanceOf(address(this))),
            int256(token1.balanceOf(address(this)))
        );
        (int256 amount0Delta, int256 amount1Delta) = pool.swap(
            address(this),
            false,
            swapAmount,
            sqrtP(6110),
            extra
        );
        //check token1 input amount
        assertEq(uint256(amount1Delta), swapAmount, "invalid USDC in");
        assertSwapState(
            ExpectedStateAfterSwap({
                pool: pool,
                token0: token0,
                token1: token1,
                userBalance0: uint256(userBalance0Before - amount0Delta),
                userBalance1: uint256(userBalance1Before - amount1Delta),
                poolBalance0: uint256(int256(poolBalance0) + amount0Delta),
                poolBalance1: uint256(int256(poolBalance1) + amount1Delta),
                sqrtPriceX96: 6113108782441498245750014589428,
                tick: 86921,
                currentLiquidity: liquidity[1].amount
            })
        );
    }

    function testBuyETHSlippageInterruption() public {
        LiquidityRange[] memory liquidity = new LiquidityRange[](1);
        liquidity[0] = liquidityRange(4545, 5500, 1 ether, 5000 ether, 5000);
        TestCaseParams memory params = TestCaseParams({
            wethBalance: 1 ether,
            usdcBalance: 5000 ether,
            currentPrice: 5000,
            liquidity: liquidity,
            transferInMintCallback: true,
            transferInSwapCallback: true,
            mintLiquidity: true
        });
        (uint256 poolBalance0, uint256 poolBalance1) = setupTestCase(params);

        uint256 swapAmount = 42 ether; // 42 USDC
        token1.mint(address(this), swapAmount);
        token1.approve(address(this), swapAmount);

        (int256 userBalance0Before, int256 userBalance1Before) = (
            int256(token0.balanceOf(address(this))),
            int256(token1.balanceOf(address(this)))
        );

        (int256 amount0Delta, int256 amount1Delta) = pool.swap(
            address(this),
            false,
            swapAmount,
            sqrtP(5002),
            extra
        );
        assertSwapState(
            ExpectedStateAfterSwap({
                pool: pool,
                token0: token0,
                token1: token1,
                userBalance0: uint256(userBalance0Before - amount0Delta),
                userBalance1: uint256(userBalance1Before - amount1Delta),
                poolBalance0: uint256(int256(poolBalance0) + amount0Delta),
                poolBalance1: uint256(int256(poolBalance1) + amount1Delta),
                sqrtPriceX96: sqrtP(5002),
                tick: tick(5002),
                currentLiquidity: liquidity[0].amount
            })
        );
    }

    //  One price range
    //
    //          5000
    //  4545 -----|----- 5500
    //
    function testBuyUSDCOnePriceRange() public {
        LiquidityRange[] memory liquidity = new LiquidityRange[](1);
        liquidity[0] = liquidityRange(4545, 5500, 1 ether, 5000 ether, 5000);
        TestCaseParams memory params = TestCaseParams({
            wethBalance: 1 ether,
            usdcBalance: 5000 ether,
            currentPrice: 5000,
            liquidity: liquidity,
            transferInMintCallback: true,
            transferInSwapCallback: true,
            mintLiquidity: true
        });
        (uint256 poolBalance0, uint256 poolBalance1) = setupTestCase(params);
        uint256 swapAmount = 0.01337 ether;
        token0.mint(address(this), swapAmount);
        token0.approve(address(this), swapAmount);
        (int256 userBalance0Before, int256 userBalance1Before) = (
            int256(token0.balanceOf(address(this))),
            int256(token1.balanceOf(address(this)))
        );
        (int256 amount0Delta, int256 amount1Delta) = pool.swap(
            address(this),
            true,
            swapAmount,
            sqrtP(4990),
            extra
        );
        // check token0 input amount
        assertEq(uint256(amount0Delta), swapAmount, "invalid ETH in");
        assertSwapState(
            ExpectedStateAfterSwap({
                pool: pool,
                token0: token0,
                token1: token1,
                userBalance0: uint256(userBalance0Before - amount0Delta),
                userBalance1: uint256(userBalance1Before - amount1Delta),
                poolBalance0: uint256(int256(poolBalance0) + amount0Delta),
                poolBalance1: uint256(int256(poolBalance1) + amount1Delta),
                sqrtPriceX96: 5598864267980327381293641469695,
                tick: 85164,
                currentLiquidity: liquidity[0].amount
            })
        );
    }

    //  Two equal price ranges
    //
    //          5000
    //  4545 -----|----- 5500
    //  4545 -----|----- 5500
    //
    function testBuyUSDCTwoEqualPriceRanges() public {
        LiquidityRange memory range = liquidityRange(
            4545,
            5500,
            1 ether,
            5000 ether,
            5000
        );
        LiquidityRange[] memory liquidity = new LiquidityRange[](2);
        liquidity[0] = range;
        liquidity[1] = range;
        TestCaseParams memory params = TestCaseParams({
            wethBalance: 2 ether,
            usdcBalance: 10000 ether,
            currentPrice: 5000,
            liquidity: liquidity,
            transferInMintCallback: true,
            transferInSwapCallback: true,
            mintLiquidity: true
        });
        (uint256 poolBalance0, uint256 poolBalance1) = setupTestCase(params);

        uint256 swapAmount = 0.01337 ether;
        token0.mint(address(this), swapAmount);
        token0.approve(address(this), swapAmount);

        (int256 userBalance0Before, int256 userBalance1Before) = (
            int256(token0.balanceOf(address(this))),
            int256(token1.balanceOf(address(this)))
        );

        (int256 amount0Delta, int256 amount1Delta) = pool.swap(
            address(this),
            true,
            swapAmount,
            sqrtP(4990),
            extra
        );
        assertEq(
            uint256(amount0Delta),
            swapAmount,
            "invalid ETH input token amount"
        );
        assertSwapState(
            ExpectedStateAfterSwap({
                pool: pool,
                token0: token0,
                token1: token1,
                userBalance0: uint256(userBalance0Before - amount0Delta),
                userBalance1: uint256(userBalance1Before - amount1Delta),
                poolBalance0: uint256(int256(poolBalance0) + amount0Delta),
                poolBalance1: uint256(int256(poolBalance1) + amount1Delta),
                sqrtPriceX96: 5600570162809008817738050929469,
                tick: 85170,
                currentLiquidity: liquidity[0].amount + liquidity[1].amount
            })
        );
    }

    //  Consecutive price ranges
    //
    //                     5000
    //             4545 -----|----- 5500
    //  4000 ----------- 4545
    //
    function testBuyUSDCConsecutivePriceRanges() public {
        LiquidityRange[] memory liquidity = new LiquidityRange[](2);
        liquidity[0] = liquidityRange(4545, 5500, 1 ether, 5000 ether, 5000);
        liquidity[1] = liquidityRange(4000, 4545, 1 ether, 5000 ether, 5000);
        TestCaseParams memory params = TestCaseParams({
            wethBalance: 2 ether,
            usdcBalance: 10000 ether,
            currentPrice: 5000,
            liquidity: liquidity,
            transferInMintCallback: true,
            transferInSwapCallback: true,
            mintLiquidity: true
        });
        (uint256 poolBalance0, uint256 poolBalance1) = setupTestCase(params);
        uint256 swapAmount = 2 ether;
        token0.mint(address(this), swapAmount);
        token0.approve(address(this), swapAmount);
        (int256 userBalance0Before, int256 userBalance1Before) = (
            int256(token0.balanceOf(address(this))),
            int256(token1.balanceOf(address(this)))
        );
        (int256 amount0Delta, int256 amount1Delta) = pool.swap(
            address(this),
            true,
            swapAmount,
            sqrtP(4000),
            extra
        );
        assertEq(uint256(amount0Delta), swapAmount, "Invalid ETH in");
        assertSwapState(
            ExpectedStateAfterSwap({
                pool: pool,
                token0: token0,
                token1: token1,
                userBalance0: uint256(userBalance0Before - amount0Delta),
                userBalance1: uint256(userBalance1Before - amount1Delta),
                poolBalance0: uint256(int256(poolBalance0) + amount0Delta),
                poolBalance1: uint256(int256(poolBalance1) + amount1Delta),
                sqrtPriceX96: 5134132205708668748264775407528,
                tick: 83430,
                currentLiquidity: liquidity[1].amount
            })
        );
    }

    //  Partially overlapping price ranges
    //
    //                5000
    //        4545 -----|----- 5500
    //  4000 ----------- 5000-1
    //
    function testBuyUSDCPartiallyOverlappingPriceRanges() public {
        LiquidityRange[] memory liquidity = new LiquidityRange[](2);
        liquidity[0] = liquidityRange(4545, 5500, 1 ether, 5000 ether, 5000);
        liquidity[1] = liquidityRange(4000, 4999, 1 ether, 5000 ether, 5000);
        TestCaseParams memory params = TestCaseParams({
            wethBalance: 2 ether,
            usdcBalance: 10000 ether,
            currentPrice: 5000,
            liquidity: liquidity,
            transferInMintCallback: true,
            transferInSwapCallback: true,
            mintLiquidity: true
        });
        (uint256 poolBalance0, uint256 poolBalance1) = setupTestCase(params);
        uint256 swapAmount = 2 ether;
        token0.mint(address(this), swapAmount);
        token0.approve(address(this), swapAmount);
        (int256 userBalance0Before, int256 userBalance1Before) = (
            int256(token0.balanceOf(address(this))),
            int256(token1.balanceOf(address(this)))
        );
        (int256 amount0Delta, int256 amount1Delta) = pool.swap(
            address(this),
            true,
            swapAmount,
            sqrtP(4000),
            extra
        );
        assertEq(uint256(amount0Delta), swapAmount, "invalid Eth in");
        assertSwapState(
            ExpectedStateAfterSwap({
                pool: pool,
                token0: token0,
                token1: token1,
                userBalance0: uint256(userBalance0Before - amount0Delta),
                userBalance1: uint256(userBalance1Before - amount1Delta),
                poolBalance0: uint256(int256(poolBalance0) + amount0Delta),
                poolBalance1: uint256(int256(poolBalance1) + amount1Delta),
                sqrtPriceX96: 5266172344592743196167223309922,
                tick: 83938,
                currentLiquidity: liquidity[1].amount
            })
        );
    }

    function testBuyUSDCSlippageInterruption() public {
        LiquidityRange[] memory liquidity = new LiquidityRange[](1);
        liquidity[0] = liquidityRange(4545, 5500, 1 ether, 5000 ether, 5000);
        TestCaseParams memory params = TestCaseParams({
            wethBalance: 1 ether,
            usdcBalance: 5000 ether,
            currentPrice: 5000,
            liquidity: liquidity,
            transferInMintCallback: true,
            transferInSwapCallback: true,
            mintLiquidity: true
        });
        (uint256 poolBalance0, uint256 poolBalance1) = setupTestCase(params);

        uint256 swapAmount = 0.01337 ether;
        token0.mint(address(this), swapAmount);
        token0.approve(address(this), swapAmount);
        (int256 userBalance0Before, int256 userBalance1Before) = (
            int256(token0.balanceOf(address(this))),
            int256(token1.balanceOf(address(this)))
        );

        (int256 amount0Delta, int256 amount1Delta) = pool.swap(
            address(this),
            true,
            swapAmount,
            sqrtP(4996),
            extra
        );
        assertSwapState(
            ExpectedStateAfterSwap({
                pool: pool,
                token0: token0,
                token1: token1,
                userBalance0: uint256(userBalance0Before - amount0Delta),
                userBalance1: uint256(userBalance1Before - amount1Delta),
                poolBalance0: uint256(int256(poolBalance0) + amount0Delta),
                poolBalance1: uint256(int256(poolBalance1) + amount1Delta),
                sqrtPriceX96: sqrtP(4996),
                tick: tick(4996),
                currentLiquidity: liquidity[0].amount
            })
        );
    }

    function testObserve() public {
        LiquidityRange[] memory liquidity = new LiquidityRange[](1);
        liquidity[0] = liquidityRange(4545, 5500, 1 ether, 5000 ether, 5000);
        TestCaseParams memory params = TestCaseParams({
            wethBalance: 1 ether,
            usdcBalance: 5000 ether,
            currentPrice: 5000,
            liquidity: liquidity,
            transferInMintCallback: true,
            transferInSwapCallback: true,
            mintLiquidity: true
        });
        (uint256 poolBalance0, uint256 poolBalance1) = setupTestCase(params);
        uint32[] memory secondsAgo;
        pool.increaseObservationCardinalityNext(3);
        uint256 swapAmount = 100 ether; //100 USDC
        token1.mint(address(this), swapAmount * 10);
        token1.approve(address(this), swapAmount * 10);

        uint256 swapAmount2 = 1 ether; // 1WETH
        token0.mint(address(this), swapAmount2 * 10);
        token0.approve(address(this), swapAmount2 * 10);

        vm.warp(2);
        pool.swap(address(this), false, swapAmount, sqrtP(6000), extra);
        vm.warp(7);
        pool.swap(address(this), true, swapAmount2, sqrtP(4000), extra);
        vm.warp(20);
        pool.swap(address(this), false, swapAmount, sqrtP(6000), extra);

        secondsAgo = new uint32[](4);
        secondsAgo[0] = 0;
        secondsAgo[1] = 13;
        secondsAgo[2] = 17;
        secondsAgo[3] = 18;
        int56[] memory tickCumulatives = pool.observe(secondsAgo);
        assertEq(tickCumulatives[0], 1607059);
        assertEq(tickCumulatives[1], 511146);
        assertEq(tickCumulatives[2], 170370);
        assertEq(tickCumulatives[3], 85176);
    }

    // //---------------------------------------------------------------------------
    // //============================== INTERNAL ===================================

    function deployPool(
        PoolParameters memory params
    ) internal returns (address _pool) {
        _pool = factory.createPool(params.token0, params.token1, params.fee);
    }

    function setupTestCase(
        TestCaseParams memory params
    ) internal returns (uint256 poolBalance0, uint256 poolBalance1) {
        token0.mint(address(this), params.wethBalance + 5 ether);
        token1.mint(address(this), params.usdcBalance + 5 ether);
        parameters = PoolParameters({
            factory: address(factory),
            token0: address(token0),
            token1: address(token1),
            tickSpacing: 60,
            fee: 3000
        });
        pool = PandaswapPool(deployPool(parameters));
        pool.initialize(sqrtP(5000));
        //set up callback params

        uint256 poolBalance0Tmp;
        uint256 poolBalance1Tmp;

        if (params.mintLiquidity) {
            console.log("minting position...");
            transferInMintCallback = params.transferInMintCallback;
            token0.approve(address(this), params.wethBalance + 5 ether);
            token1.approve(address(this), params.usdcBalance + 5 ether);
            for (uint256 i = 0; i < params.liquidity.length; i++) {
                (poolBalance0Tmp, poolBalance1Tmp) = pool.mint(
                    address(this),
                    params.liquidity[i].lowerTick,
                    params.liquidity[i].upperTick,
                    params.liquidity[i].amount,
                    extra
                );
                poolBalance0 += poolBalance0Tmp;
                poolBalance1 += poolBalance1Tmp;
            }
        }
        transferInSwapCallback = params.transferInSwapCallback;
    }

    // //---------------------------------------------------------------------------
    // //============================== CALLBACK ===================================
    function pandaswapSwapCallback(
        int256 amount0,
        int256 amount1,
        bytes calldata data
    ) public {
        if (transferInSwapCallback) {
            CallbackData memory _data = abi.decode(data, (CallbackData));
            if (amount0 > 0) {
                IERC20(_data.token0).transferFrom(
                    _data.payer,
                    msg.sender,
                    uint256(amount0)
                );
            }
            if (amount1 > 0) {
                IERC20(_data.token1).transferFrom(
                    _data.payer,
                    msg.sender,
                    uint256(amount1)
                );
            }
        }
    }

    function pandaswapMintCallback(
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) public {
        if (transferInMintCallback) {
            CallbackData memory _extra = abi.decode(data, (CallbackData));
            IERC20(_extra.token0).transferFrom(
                _extra.payer,
                msg.sender,
                amount0
            );
            IERC20(_extra.token1).transferFrom(
                _extra.payer,
                msg.sender,
                amount1
            );
        }
        console.log(amount0, amount1);
    }
}
