// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../src/PandaswapPool.sol";
import "forge-std/Test.sol";
import "./ERC20Mintable.sol";
import "./TestUtils.sol";
import "./PandaswapPool.Utils.sol";
import "../src/PandaswapFactory.sol";
import "../src/interfaces/IPandaswapManager.sol";
import "../src/interfaces/IPandaswapPoolDeployer.sol";

contract PandaswapPoolTest is
    Test,
    TestUtils,
    PandaswapPoolUtils,
    IPandaswapPoolDeployer
{
    ERC20Mintable token0;
    ERC20Mintable token1;
    PandaswapPool pool;
    PandaswapFactory factory;
    PoolParameters public parameters;

    bool transferInMintCallback = true;
    bool flashCallbackCalled = false;

    function setUp() public {
        console.log("deploying...");
        token1 = new ERC20Mintable("Wrapped Ether", "WETH", 18);
        token0 = new ERC20Mintable("USDC", "USDC", 18);
        factory = new PandaswapFactory();
        console.log(address(token0), address(token1));
    }

    function testInitialize() public {
        parameters = PoolParameters({
            factory: address(this),
            token0: address(token0),
            token1: address(token1),
            tickSpacing: 1,
            fee: 3000
        });
        pool = PandaswapPool(deployPool(parameters));
        pool.initialize(sqrtP(5000));
        (uint160 sqrtPriceX96, int24 tick, , , ) = pool.slot0();
        assertEq(
            sqrtPriceX96,
            5602277097478613991869082763264,
            "invalid sqrtPriceX96"
        );
        assertEq(tick, 85176, "invalid tick");
        vm.expectRevert(encodeError("AlreadyInitialized()"));
        pool.initialize(sqrtP(42));
    }

    function testMintinRange() public {
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
        assertMintState(
            ExpectedStateAfterMint({
                pool: pool,
                token0: token0,
                token1: token1,
                amount0: poolBalance0,
                amount1: poolBalance1,
                lowerTick: liquidity[0].lowerTick,
                upperTick: liquidity[0].upperTick,
                positionLiquidity: liquidity[0].amount,
                currentLiquidity: liquidity[0].amount,
                sqrtPriceX96: sqrtP(5000),
                tick: tick(5000)
            })
        );
    }

    function testMintRangeBelow() public {
        LiquidityRange[] memory liquidity = new LiquidityRange[](1);
        liquidity[0] = liquidityRange(4000, 4996, 1 ether, 5000 ether, 5000);
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
        // check no token0 is minted in pool
        assertEq(poolBalance0, 0 ether, "incorrect token0 deposited amount");
        assertMintState(
            ExpectedStateAfterMint({
                pool: pool,
                token0: token0,
                token1: token1,
                amount0: poolBalance0,
                amount1: poolBalance1,
                lowerTick: liquidity[0].lowerTick,
                upperTick: liquidity[0].upperTick,
                positionLiquidity: liquidity[0].amount,
                currentLiquidity: 0,
                sqrtPriceX96: sqrtP(5000),
                tick: tick(5000)
            })
        );
    }

    function testMintRangeAbove() public {
        LiquidityRange[] memory liquidity = new LiquidityRange[](1);
        liquidity[0] = liquidityRange(5001, 6250, 1 ether, 5000 ether, 5000);
        TestCaseParams memory params = TestCaseParams({
            wethBalance: 10 ether,
            usdcBalance: 5000 ether,
            currentPrice: 5000,
            liquidity: liquidity,
            transferInMintCallback: true,
            transferInSwapCallback: true,
            mintLiquidity: true
        });
        (uint256 poolBalance0, uint256 poolBalance1) = setupTestCase(params);
        //check no token1 is minted
        assertEq(poolBalance1, 0 ether, "incorrect token1 deposited amount");
        assertMintState(
            ExpectedStateAfterMint({
                pool: pool,
                token0: token0,
                token1: token1,
                amount0: poolBalance0,
                amount1: poolBalance1,
                lowerTick: liquidity[0].lowerTick,
                upperTick: liquidity[0].upperTick,
                positionLiquidity: liquidity[0].amount,
                currentLiquidity: 0,
                sqrtPriceX96: sqrtP(5000),
                tick: tick(5000)
            })
        );
    }

    //
    //          5000
    //   4545 ----|---- 5500
    // 4000 ------|------ 6250
    //

    function testMintOverlappingRanges() public {
        LiquidityRange[] memory liquidity = new LiquidityRange[](2);
        liquidity[0] = liquidityRange(4545, 5500, 1 ether, 5000 ether, 5000);
        liquidity[1] = liquidityRange(
            4000,
            6250,
            (liquidity[0].amount * 75) / 100
        );
        TestCaseParams memory params = TestCaseParams({
            wethBalance: 3 ether,
            usdcBalance: 15000 ether,
            currentPrice: 5000,
            liquidity: liquidity,
            transferInMintCallback: true,
            transferInSwapCallback: true,
            mintLiquidity: true
        });
        (uint256 poolBalance0, uint256 poolBalance1) = setupTestCase(params);
        assertMintState(
            ExpectedStateAfterMint({
                pool: pool,
                token0: token0,
                token1: token1,
                amount0: poolBalance0,
                amount1: poolBalance1,
                lowerTick: tick60(4545),
                upperTick: tick60(5500),
                positionLiquidity: liquidity[0].amount,
                currentLiquidity: liquidity[0].amount + liquidity[1].amount,
                sqrtPriceX96: sqrtP(5000),
                tick: tick(5000)
            })
        );
        assertMintState(
            ExpectedStateAfterMint({
                pool: pool,
                token0: token0,
                token1: token1,
                amount0: poolBalance0,
                amount1: poolBalance1,
                lowerTick: tick60(4000),
                upperTick: tick60(6250),
                positionLiquidity: liquidity[1].amount,
                currentLiquidity: liquidity[0].amount + liquidity[1].amount,
                sqrtPriceX96: sqrtP(5000),
                tick: tick(5000)
            })
        );
    }

    function testMintInvalidTickRangeLower() public {
        parameters = PoolParameters({
            factory: address(this),
            token0: address(token0),
            token1: address(token1),
            tickSpacing: 60,
            fee: 3000
        });
        pool = PandaswapPool(deployPool(parameters));
        vm.expectRevert(encodeError("InvalidTickRange()"));
        pool.mint(address(this), -887273, 0, 0, "");
    }

    function testMintInvalidTickRangeUpper() public {
        parameters = PoolParameters({
            factory: address(this),
            token0: address(token0),
            token1: address(token1),
            tickSpacing: 60,
            fee: 3000
        });
        pool = PandaswapPool(deployPool(parameters));
        vm.expectRevert(encodeError("InvalidTickRange()"));
        pool.mint(address(this), 887273, 0, 0, "");
    }

    function testMintZeroLiquidity() public {
        parameters = PoolParameters({
            factory: address(this),
            token0: address(token0),
            token1: address(token1),
            tickSpacing: 60,
            fee: 3000
        });
        pool = PandaswapPool(deployPool(parameters));
        vm.expectRevert(encodeError("ZeroLiquidity()"));
        pool.mint(address(this), 0, 1, 0, "");
    }

    function testMintInsufficientTokenBalance() public {
        LiquidityRange[] memory liquidity = new LiquidityRange[](1);
        liquidity[0] = liquidityRange(4545, 5500, 1 ether, 5000 ether, 5000);
        parameters = PoolParameters({
            factory: address(this),
            token0: address(token0),
            token1: address(token1),
            tickSpacing: 60,
            fee: 3000
        });
        pool = PandaswapPool(deployPool(parameters));
        vm.expectRevert();
        pool.mint(
            address(this),
            liquidity[0].lowerTick,
            liquidity[0].upperTick,
            liquidity[0].amount,
            ""
        );
    }

    function testFlash() public {
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
        setupTestCase(params);
        pool.flash(
            0.1 ether,
            1000 ether,
            abi.encode(uint256(0.1 ether), uint256(1000 ether))
        );
        assertTrue(flashCallbackCalled, "flash callback wasnt called");
    }

    // //---------------------------------------------------------------------------
    // //============================== INTERNAL ===================================

    function setupTestCase(
        TestCaseParams memory params
    ) internal returns (uint256 poolBalance0, uint256 poolBalance1) {
        token0.mint(address(this), params.wethBalance + 5 ether);
        token1.mint(address(this), params.usdcBalance + 5 ether);
        parameters = PoolParameters({
            factory: address(this),
            token0: address(token0),
            token1: address(token1),
            tickSpacing: 60,
            fee: 3000
        });
        pool = PandaswapPool(deployPool(parameters));
        pool.initialize(sqrtP(5000));
        //set up callback params
        IPandaswapManager.CallbackData memory extra = IPandaswapManager
            .CallbackData({
                token0: address(token0),
                token1: address(token1),
                payer: address(this)
            });
        bytes memory data = abi.encode(extra);

        uint256 poolBalance0Tmp;
        uint256 poolBalance1Tmp;

        if (params.mintLiquidity) {
            console.log("minting position...");
            token0.approve(address(this), params.wethBalance + 5 ether);
            token1.approve(address(this), params.usdcBalance + 5 ether);
            for (uint256 i = 0; i < params.liquidity.length; i++) {
                (poolBalance0Tmp, poolBalance1Tmp) = pool.mint(
                    address(this),
                    params.liquidity[i].lowerTick,
                    params.liquidity[i].upperTick,
                    params.liquidity[i].amount,
                    data
                );
                poolBalance0 += poolBalance0Tmp;
                poolBalance1 += poolBalance1Tmp;
            }
        }
    }

    // //---------------------------------------------------------------------------
    // //============================== CALLBACK ===================================

    function deployPool(
        PoolParameters memory params
    ) internal returns (address _pool) {
        _pool = factory.createPool(params.token0, params.token1, params.fee);
    }

    function pandaswapMintCallback(
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) public {
        if (transferInMintCallback) {
            IPandaswapManager.CallbackData memory extra = abi.decode(
                data,
                (IPandaswapManager.CallbackData)
            );
            IERC20(extra.token0).transferFrom(extra.payer, msg.sender, amount0);
            IERC20(extra.token1).transferFrom(extra.payer, msg.sender, amount1);
        }
        console.log(amount0, amount1);
    }

    function pandaswapFlashCallback(
        uint256 fee0,
        uint256 fee1,
        bytes calldata data
    ) public {
        (uint256 amount0, uint256 amount1) = abi.decode(
            data,
            (uint256, uint256)
        );
        if (amount0 > 0) token0.transfer(msg.sender, amount0 + fee0);
        if (amount1 > 0) token1.transfer(msg.sender, amount1 + fee1);
        flashCallbackCalled = true;
    }
}
