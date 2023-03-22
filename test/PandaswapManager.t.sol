//SPDX-License-Identifier:MIT
pragma solidity ^0.8.14;
import "forge-std/Test.sol";
import "./TestUtils.sol";
import "./ERC20Mintable.sol";
import "../src/PandaswapFactory.sol";
import "../src/PandaswapManager.sol";
import "../src/interfaces/IPandaswapMintCallback.sol";
import "./PandaswapPool.Utils.sol";
import "../src/lib/Position.sol";
import "../src/lib/LiquidityMath.sol";
import "../src/lib/BytesLib.sol";

contract PandaswapManagerTest is Test, TestUtils {
    using BytesLib for bytes;
    ERC20Mintable weth;
    ERC20Mintable usdc;
    ERC20Mintable panda;
    PandaswapFactory factory;
    PandaswapManager manager;
    PandaswapPool pool;
    bool transferInMintCallback = true;
    bool transferInSwapCallback = true;

    struct TestCaseParams {
        uint256 wethBalance;
        uint256 usdcBalance;
        uint256 currentPrice;
        PandaswapManager.MintParams[] mints;
        bool transferInSwapCallback;
        bool transferInMintCallback;
        bool mintLiquidity;
    }

    function setUp() public {
        usdc = new ERC20Mintable("USDC", "USDC", 18);
        console.log("usdc", address(usdc));
        weth = new ERC20Mintable("Ether", "ETH", 18);
        console.log("weth", address(weth));
        panda = new ERC20Mintable("Pandaswap Coin", "Panda", 18);
        console.log("panda", address(panda));
        factory = new PandaswapFactory();
        manager = new PandaswapManager(address(factory));
    }

    // //---------------------------------------------------------------------------
    // //===========================     TEST_MINT =================================

    function testMintInRange() public {
        PandaswapManager.MintParams[]
            memory mints = new PandaswapManager.MintParams[](1);
        mints[0] = mintParams60(4545, 5000, 1 ether, 5000 ether);
        TestCaseParams memory params = TestCaseParams({
            wethBalance: 1 ether,
            usdcBalance: 5000 ether,
            currentPrice: 5000,
            mints: mints,
            transferInMintCallback: true,
            transferInSwapCallback: true,
            mintLiquidity: true
        });
        (uint256 poolBalance0, uint256 poolBalance1) = setupTestCase(params);
        assertMintState(
            ExpectedStateAfterMint({
                pool: pool,
                token0: weth,
                token1: usdc,
                amount0: poolBalance0,
                amount1: poolBalance1,
                lowerTick: mints[0].lowerTick,
                upperTick: mints[0].upperTick,
                positionLiquidity: liquidity60(mints[0], 5000),
                currentLiquidity: liquidity60(mints[0], 5000),
                sqrtPriceX96: sqrtP(5000),
                tick: tick(5000)
            })
        );
    }

    function testMintRangeBelow() public {
        PandaswapManager.MintParams[]
            memory mints = new PandaswapManager.MintParams[](1);
        mints[0] = mintParams60(4000, 4996, 1 ether, 5000 ether);
        TestCaseParams memory params = TestCaseParams({
            wethBalance: 1 ether,
            usdcBalance: 5000 ether,
            currentPrice: 5000,
            mints: mints,
            transferInMintCallback: true,
            transferInSwapCallback: true,
            mintLiquidity: true
        });
        (uint256 poolBalance0, uint256 poolBalance1) = setupTestCase(params);
        //verify correct token0 mint amount
        assertEq(poolBalance0, 0, "invalid token0 balance in pool");
        assertMintState(
            ExpectedStateAfterMint({
                pool: pool,
                token0: weth,
                token1: usdc,
                amount0: poolBalance0,
                amount1: poolBalance1,
                lowerTick: mints[0].lowerTick,
                upperTick: mints[0].upperTick,
                positionLiquidity: liquidity60(mints[0], 5000),
                currentLiquidity: 0,
                sqrtPriceX96: sqrtP(5000),
                tick: tick(5000)
            })
        );
    }

    // //---------------------------------------------------------------------------
    // //===========================     TEST_SWAP =================================
    function testSwapBuyEth() public {
        PandaswapManager.MintParams[]
            memory mints = new PandaswapManager.MintParams[](1);
        mints[0] = mintParams60(4545, 5500, 1 ether, 5000 ether);
        TestCaseParams memory params = TestCaseParams({
            wethBalance: 1 ether,
            usdcBalance: 5000 ether,
            currentPrice: 5000,
            mints: mints,
            transferInMintCallback: true,
            transferInSwapCallback: true,
            mintLiquidity: true
        });
        (uint256 poolBalance0, uint256 poolBalance1) = setupTestCase(params);
        uint256 swapAmount = 42 ether;
        usdc.mint(address(this), swapAmount + 1 ether);
        usdc.approve(address(manager), swapAmount + 1 ether);
        (uint256 userBalance0Before, uint256 userBalance1Before) = (
            weth.balanceOf(address(this)),
            usdc.balanceOf(address(this))
        );
        uint256 amountOut = manager.swapSingle(
            PandaswapManager.SwapSingleParams({
                tokenIn: address(usdc),
                tokenOut: address(weth),
                tickSpacing: 60,
                amountIn: swapAmount,
                sqrtPriceLimitX96: sqrtP(5004)
            })
        );
        assertSwapState(
            ExpectedStateAfterSwap({
                pool: pool,
                token0: weth,
                token1: usdc,
                userBalance0: userBalance0Before + amountOut,
                userBalance1: userBalance1Before - swapAmount,
                poolBalance0: poolBalance0 - amountOut,
                poolBalance1: poolBalance1 + swapAmount,
                sqrtPriceX96: 5604429046402228950611610935846,
                tick: 85183,
                currentLiquidity: liquidity60(mints[0], 5000)
            })
        );
    }

    function testSwapBuyUSDC() public {
        PandaswapManager.MintParams[]
            memory mints = new PandaswapManager.MintParams[](1);
        mints[0] = mintParams60(4545, 5500, 1 ether, 5000 ether);
        TestCaseParams memory params = TestCaseParams({
            wethBalance: 1 ether,
            usdcBalance: 5000 ether,
            currentPrice: 5000,
            mints: mints,
            transferInMintCallback: true,
            transferInSwapCallback: true,
            mintLiquidity: true
        });
        (uint256 poolBalance0, uint256 poolBalance1) = setupTestCase(params);
        uint256 swapAmount = 0.01337 ether;
        weth.mint(address(this), swapAmount + 1 ether);
        weth.approve(address(manager), swapAmount + 1 ether);
        (uint256 userBalance0Before, uint256 userBalance1Before) = (
            weth.balanceOf(address(this)),
            usdc.balanceOf(address(this))
        );
        uint256 amountOut = manager.swapSingle(
            PandaswapManager.SwapSingleParams({
                tokenIn: address(weth),
                tokenOut: address(usdc),
                tickSpacing: 60,
                amountIn: swapAmount,
                sqrtPriceLimitX96: sqrtP(4993)
            })
        );
        assertSwapState(
            ExpectedStateAfterSwap({
                pool: pool,
                token0: weth,
                token1: usdc,
                userBalance0: userBalance0Before - swapAmount,
                userBalance1: userBalance1Before + amountOut,
                poolBalance0: poolBalance0 + swapAmount,
                poolBalance1: poolBalance1 - amountOut,
                sqrtPriceX96: 5598854004958668990019104567840,
                tick: 85163,
                currentLiquidity: liquidity60(mints[0], 5000)
            })
        );
    }

    function testSwapBuyMultiPool() public {
        PandaswapManager.MintParams[]
            memory mints = new PandaswapManager.MintParams[](1);
        mints[0] = mintParams60(4545, 5500, 1 ether, 5000 ether);
        TestCaseParams memory params = TestCaseParams({
            wethBalance: 1 ether,
            usdcBalance: 5000 ether,
            currentPrice: 5000,
            mints: mints,
            transferInMintCallback: true,
            transferInSwapCallback: true,
            mintLiquidity: true
        });
        (uint256 poolBalance0, uint256 poolBalance1) = setupTestCase(params);
        //Deploy WETH/UNI pool
        weth.mint(address(this), 10 ether);
        weth.approve(address(manager), 10 ether);
        panda.mint(address(this), 100 ether);
        panda.approve(address(manager), 100 ether);
        address poolAddress = factory.createPool(
            address(weth),
            address(panda),
            60
        );
        PandaswapPool pandaPool = PandaswapPool(poolAddress);
        pandaPool.initialize(sqrtP(10));
        (uint256 poolBalance2, uint256 poolBalance3) = manager.mint(
            mintParams60(
                address(weth),
                address(panda),
                7,
                13,
                10 ether,
                100 ether
            )
        );
        //SwapAmount in Panda
        uint256 swapAmount = 2.5 ether;
        panda.mint(address(this), swapAmount);
        panda.approve(address(manager), swapAmount);
        //Create Swap Path: panda-60->Weth-60->Usdc
        bytes memory path = bytes.concat(
            bytes20(address(panda)),
            bytes3(uint24(60)),
            bytes20(address(weth)),
            bytes3(uint24(60)),
            bytes20(address(usdc))
        );
        console.log("swapping path:");
        console.logBytes(path);
        (
            uint256 userBalance0Before,
            uint256 userBalance1Before,
            uint256 userBalance2Before
        ) = (
                weth.balanceOf(address(this)),
                usdc.balanceOf(address(this)),
                panda.balanceOf(address(this))
            );
        uint256 amountOut = manager.swap(
            PandaswapManager.SwapParams({
                path: path,
                recipient: address(this),
                amountIn: swapAmount,
                minAmountOut: 0
            })
        );
        assertSwapState(
            ExpectedStateAfterSwap({
                pool: pool,
                token0: weth,
                token1: usdc,
                userBalance0: userBalance0Before,
                userBalance1: userBalance1Before + amountOut,
                poolBalance0: poolBalance0 + 0.248978073953125685 ether,
                poolBalance1: poolBalance1 - amountOut,
                sqrtPriceX96: 5539210836162906471414991525125,
                tick: 84949,
                currentLiquidity: 1546311247949719370887
            })
        );
        assertSwapState(
            ExpectedStateAfterSwap({
                pool: pandaPool,
                token0: weth,
                token1: panda,
                userBalance0: userBalance0Before,
                userBalance1: userBalance2Before - swapAmount,
                poolBalance0: poolBalance2 - 0.248978073953125685 ether,
                poolBalance1: poolBalance3 + swapAmount,
                sqrtPriceX96: 251569791264246604334106847322,
                tick: 23108,
                currentLiquidity: 192611247052046431504
            })
        );
    }

    // //---------------------------------------------------------------------------
    // //=============================  INTERNAL ===================================

    function mintParams60(
        uint256 lowerPrice,
        uint256 upperPrice,
        uint256 amount0,
        uint256 amount1
    ) internal view returns (PandaswapManager.MintParams memory params) {
        params = mintParams60(
            address(weth),
            address(usdc),
            lowerPrice,
            upperPrice,
            amount0,
            amount1
        );
    }

    function liquidity60(
        PandaswapManager.MintParams memory params,
        uint256 currentPrice
    ) internal pure returns (uint128 _liquidity) {
        _liquidity = LiquidityMath.getLiquidityForAmounts(
            sqrtP(currentPrice),
            sqrtP60FromTick(params.lowerTick),
            sqrtP60FromTick(params.upperTick),
            params.amount0Desired,
            params.amount1Desired
        );
    }

    function setupTestCase(
        TestCaseParams memory params
    ) internal returns (uint256 poolBalance0, uint256 poolBalance1) {
        // mint tokens for user
        weth.mint(address(this), params.wethBalance + 1 ether);
        usdc.mint(address(this), params.usdcBalance + 1 ether);
        // deploy pool contract
        address poolAddress = factory.createPool(
            address(weth),
            address(usdc),
            60
        );
        pool = PandaswapPool(poolAddress);
        pool.initialize(sqrtP(params.currentPrice));
        // mint liquidity
        if (params.mintLiquidity) {
            weth.approve(address(manager), params.wethBalance + 1 ether);
            usdc.approve(address(manager), params.usdcBalance + 1 ether);
            uint256 poolBalance0Tmp;
            uint256 poolBalance1Tmp;
            transferInMintCallback = params.transferInMintCallback;
            for (uint256 i = 0; i < params.mints.length; i++) {
                (poolBalance0Tmp, poolBalance1Tmp) = manager.mint(
                    params.mints[i]
                );
                poolBalance0 += poolBalance0Tmp;
                poolBalance1 += poolBalance1Tmp;
            }
        }
        transferInSwapCallback = params.transferInSwapCallback;
    }
}
