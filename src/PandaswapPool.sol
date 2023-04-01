// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./lib/Tick.sol";
import "./lib/Position.sol";
import "./lib/TickBitmap.sol";
import "./interfaces/IPandaswapMintCallback.sol";
import "./interfaces/IPandaswapSwapCallback.sol";
import "./interfaces/IERC20.sol";
import "./lib/Math.sol";
import "./lib/TickMath.sol";
import "./lib/SwapMath.sol";
import "./lib/LiquidityMath.sol";
import "forge-std/Test.sol";
import "./interfaces/IPandaswapFlashCallback.sol";
import "./interfaces/IPandaswapPoolDeployer.sol";
import "./lib/FixedPoint128.sol";
import "./lib/Oracle.sol";

contract PandaswapPool is Test {
    using Tick for mapping(int24 => Tick.Info);
    using Position for mapping(bytes32 => Position.Info);
    using Position for Position.Info;
    using TickBitmap for mapping(int16 => uint256);
    using Oracle for Oracle.Observation[65535];

    int24 internal constant MIN_TICK = -887272;
    int24 internal constant MAX_TICK = -MIN_TICK;

    //Pool tokens, immutable
    address public immutable factory;
    address public immutable token0;
    address public immutable token1;
    uint24 public immutable tickSpacing;
    uint24 public immutable fee;
    //accumulated fee variables
    uint256 public feeGrowthGlobal0X128;
    uint256 public feeGrowthGlobal1X128;

    //Packing variables that are read together
    struct Slot0 {
        // Current sqrt(P)
        uint160 sqrtPriceX96;
        // Current tick
        int24 tick;
        // Most recent observation index
        uint16 observationIndex;
        // Maximum number of observations
        uint16 observationCardinality;
        // Next maximum number of observations
        uint16 observationCardinalityNext;
    }
    Slot0 public slot0;

    struct SwapState {
        uint256 amountSpecifiedRemaining;
        uint256 amountCalculated;
        uint160 sqrtPriceX96;
        int24 tick;
        uint128 liquidity;
        uint256 feeGrowthGlobalX128;
    }
    struct StepState {
        uint160 sqrtPriceStartX96;
        int24 nextTick;
        uint160 sqrtPriceNextX96;
        uint256 amountIn;
        uint256 amountOut;
        uint256 feeAmount;
        bool initialized;
    }
    struct ModifyPositionParams {
        address owner;
        int24 lowerTick;
        int24 upperTick;
        int128 liquidityDelta;
    }

    //Amount of liquidity, L.
    uint128 public liquidity;

    //Ticks info
    mapping(int24 => Tick.Info) public ticks;
    //Positions info
    mapping(bytes32 => Position.Info) public positions;
    //TickBitmap
    mapping(int16 => uint256) public tickBitmap;
    //mapping observations
    Oracle.Observation[65535] public observations;

    event Mint(
        address sender,
        address indexed owner,
        int24 indexed tickLower,
        int24 indexed tickUpper,
        uint128 amount,
        uint256 amount0,
        uint256 amount1
    );
    event Swap(
        address sender,
        address indexed recipient,
        int256 indexed amount0,
        int256 indexed amount1,
        uint160 sqrtPriceX96,
        uint128 liquidity,
        int24 tick
    );
    event Burn(
        address indexed owner,
        int24 indexed tickLower,
        int24 indexed tickUpper,
        uint128 amount,
        uint256 amount0,
        uint256 amount1
    );
    event Collect(
        address indexed owner,
        address recipient,
        int24 indexed tickLower,
        int24 indexed tickUpper,
        uint256 amount0,
        uint256 amount1
    );
    event Flash(address sender, uint256 amount0, uint256 amount1);
    event IncreaseObservationCardinalityNext(
        uint16 ObservationCardinalityNextOld,
        uint16 ObservationCardinalityNextNew
    );

    error InvalidTickRange();
    error ZeroLiquidity();
    error InsufficientInputAmount();
    error NotEnoughLiquidity();
    error InvalidPriceLimit();
    error AlreadyInitialized();

    constructor() {
        (factory, token0, token1, tickSpacing, fee) = IPandaswapPoolDeployer(
            msg.sender
        ).parameters();
    }

    function initialize(uint160 sqrtPriceX96) public {
        if (slot0.sqrtPriceX96 != 0) revert AlreadyInitialized();
        int24 tick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);
        (uint16 cardinality, uint16 cardinalityNext) = observations.initialize(
            _blockTimestamp()
        );
        slot0 = Slot0({
            sqrtPriceX96: sqrtPriceX96,
            tick: tick,
            observationIndex: 0,
            observationCardinality: cardinality,
            observationCardinalityNext: cardinalityNext
        });
    }

    /// @notice Adds liquidity for the given owner/lowerTick/upperTick/amount of liquidity

    function mint(
        address owner,
        int24 lowerTick,
        int24 upperTick,
        uint128 amount,
        bytes calldata data
    ) external returns (uint256 amount0, uint256 amount1) {
        //Check validity of price range input and liquidity input
        if (
            lowerTick >= upperTick ||
            lowerTick < MIN_TICK ||
            upperTick > MAX_TICK
        ) revert InvalidTickRange();
        if (amount == 0) revert ZeroLiquidity();
        // Update user ticks, tickBitmap, and position
        (, int256 amount0Int, int256 amount1Int) = _modifyPosition(
            ModifyPositionParams({
                owner: owner,
                lowerTick: lowerTick,
                upperTick: upperTick,
                liquidityDelta: int128(amount)
            })
        );
        amount0 = uint256(amount0Int);
        amount1 = uint256(amount1Int);
        uint256 balance0Before;
        uint256 balance1Before;
        if (amount0 > 0) balance0Before = balance0();
        if (amount1 > 0) balance1Before = balance1();
        IPandaswapMintCallback(msg.sender).pandaswapMintCallback(
            amount0,
            amount1,
            data
        );
        console.log(balance0());
        console.log(balance1());
        if (amount0 > 0 && balance0Before + amount0 < balance0())
            revert InsufficientInputAmount();
        if (amount1 > 0 && balance1Before + amount1 < balance1())
            revert InsufficientInputAmount();
        emit Mint(
            msg.sender,
            owner,
            lowerTick,
            upperTick,
            amount,
            amount0,
            amount1
        );
    }

    function burn(
        int24 lowerTick,
        int24 upperTick,
        uint128 amount
    ) public returns (uint256 amount0, uint256 amount1) {
        (
            Position.Info storage position,
            int256 amount0Int,
            int256 amount1Int
        ) = _modifyPosition(
                ModifyPositionParams({
                    owner: msg.sender,
                    lowerTick: lowerTick,
                    upperTick: upperTick,
                    liquidityDelta: -(int128(amount))
                })
            );
        amount0 = uint256(amount0Int);
        amount1 = uint256(amount1Int);
        if (amount0 > 0 || amount1 > 0) {
            (position.tokensOwed0, position.tokensOwed1) = (
                position.tokensOwed0 + uint128(amount0),
                position.tokensOwed1 + uint128(amount1)
            );
        }
        emit Burn(msg.sender, lowerTick, upperTick, amount, amount0, amount1);
    }

    function collect(
        address recipient,
        int24 lowerTick,
        int24 upperTick,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) public returns (uint128 amount0, uint128 amount1) {
        Position.Info storage position = positions.get(
            msg.sender,
            lowerTick,
            upperTick
        );
        amount0 = amount0Requested > position.tokensOwed0
            ? position.tokensOwed0
            : amount0Requested;
        amount1 = amount1Requested > position.tokensOwed1
            ? position.tokensOwed1
            : amount1Requested;
        if (amount0 > 0) {
            position.tokensOwed0 -= amount0;
            IERC20(token0).transfer(recipient, amount0);
        }
        if (amount1 < 0) {
            position.tokensOwed1 -= amount1;
            IERC20(token1).transfer(recipient, amount1);
        }
        emit Collect(
            msg.sender,
            recipient,
            lowerTick,
            upperTick,
            amount0,
            amount1
        );
    }

    function balance0() internal returns (uint256 balance) {
        balance = IERC20(token0).balanceOf(address(this));
    }

    function balance1() internal returns (uint256 balance) {
        balance = IERC20(token1).balanceOf(address(this));
    }

    function flash(
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) public {
        uint256 fee0 = Math.mulDivRoundingUp(amount0, fee, 1e6);
        uint256 fee1 = Math.mulDivRoundingUp(amount1, fee, 1e6);
        console.log(fee0, fee1);
        uint256 balance0Before = IERC20(token0).balanceOf(address(this));
        uint256 balance1Before = IERC20(token1).balanceOf(address(this));
        if (amount0 > 0) IERC20(token0).transfer(msg.sender, amount0);
        if (amount1 > 0) IERC20(token1).transfer(msg.sender, amount1);
        IPandaswapFlashCallback(msg.sender).pandaswapFlashCallback(
            fee0,
            fee1,
            data
        );
        require(
            IERC20(token0).balanceOf(address(this)) >= balance0Before + fee0
        );
        require(
            IERC20(token1).balanceOf(address(this)) >= balance1Before + fee1
        );
        emit Flash(msg.sender, amount0, amount1);
    }

    function swap(
        address recipient,
        bool zeroForOne,
        uint256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) public returns (int256 amount0, int256 amount1) {
        Slot0 memory _slot0 = slot0;
        uint128 _liquidity = liquidity;
        if (
            zeroForOne
                ? sqrtPriceLimitX96 > _slot0.sqrtPriceX96 ||
                    sqrtPriceLimitX96 < TickMath.MIN_SQRT_RATIO
                : sqrtPriceLimitX96 < _slot0.sqrtPriceX96 ||
                    sqrtPriceLimitX96 > TickMath.MAX_SQRT_RATIO
        ) revert InvalidPriceLimit();
        SwapState memory state = SwapState({
            amountSpecifiedRemaining: amountSpecified,
            amountCalculated: 0,
            sqrtPriceX96: _slot0.sqrtPriceX96,
            tick: _slot0.tick,
            liquidity: liquidity,
            feeGrowthGlobalX128: zeroForOne
                ? feeGrowthGlobal0X128
                : feeGrowthGlobal1X128
        });
        console.log("current tick", uint24(_slot0.tick));
        console.log("looping swap..."); //for testing purpose
        console.log("current liquidity", _liquidity);
        while (
            state.amountSpecifiedRemaining > 0 &&
            state.sqrtPriceX96 != sqrtPriceLimitX96
        ) {
            StepState memory step;
            (step.nextTick, step.initialized) = tickBitmap
                .nextInitializedTickWithinOneWord(
                    state.tick,
                    int24(tickSpacing),
                    zeroForOne
                );
            step.sqrtPriceNextX96 = TickMath.getSqrtRatioAtTick(step.nextTick);
            (
                state.sqrtPriceX96,
                step.amountIn,
                step.amountOut,
                step.feeAmount
            ) = SwapMath.computeSwapStep(
                state.sqrtPriceX96,
                (
                    zeroForOne
                        ? step.sqrtPriceNextX96 < sqrtPriceLimitX96
                        : step.sqrtPriceNextX96 > sqrtPriceLimitX96
                )
                    ? sqrtPriceLimitX96
                    : step.sqrtPriceNextX96,
                liquidity,
                state.amountSpecifiedRemaining,
                fee
            );
            console.log("step nextTick:", uint24(step.nextTick));
            console.log("step amountIn:", step.amountIn);
            state.amountSpecifiedRemaining -= step.amountIn + step.feeAmount;
            console.log(
                "amountSpecifiedRemaining:",
                state.amountSpecifiedRemaining
            );
            state.amountCalculated += step.amountOut;
            console.log("amountCalculated:", state.amountCalculated);
            if (state.liquidity > 0) {
                state.feeGrowthGlobalX128 += mulDiv(
                    step.feeAmount,
                    FixedPoint128.Q128,
                    state.liquidity
                );
            }
            if (state.sqrtPriceX96 == step.sqrtPriceNextX96) {
                if (step.initialized) {
                    int128 liquidityDelta = ticks.cross(step.nextTick);
                    if (liquidityDelta < 0) {
                        console.log(
                            "liquidity Delta: -",
                            uint128(-liquidityDelta)
                        );
                    } else {
                        console.log(
                            "liquidity Dealta:",
                            uint128(liquidityDelta)
                        );
                    }

                    if (zeroForOne) liquidityDelta = -liquidityDelta;
                    state.liquidity = LiquidityMath.addLiquidity(
                        state.liquidity,
                        liquidityDelta
                    );
                    console.log("liquidity updated to:", state.liquidity);
                    if (state.liquidity == 0) revert NotEnoughLiquidity(); // This check is not implemented in UniswapV3pool.sol
                }

                state.tick = zeroForOne ? step.nextTick - 1 : step.nextTick;
            } else {
                state.tick = TickMath.getTickAtSqrtRatio(state.sqrtPriceX96);
            }
        }
        if (state.tick != _slot0.tick) {
            (
                uint16 observationIndex,
                uint16 observationCardinality
            ) = observations.write(
                    _slot0.observationIndex,
                    _blockTimestamp(),
                    _slot0.tick,
                    _slot0.observationCardinality,
                    _slot0.observationCardinalityNext
                );
            (
                slot0.sqrtPriceX96,
                slot0.tick,
                slot0.observationIndex,
                slot0.observationCardinality
            ) = (
                state.sqrtPriceX96,
                state.tick,
                observationIndex,
                observationCardinality
            );
        }
        if (_liquidity != state.liquidity) liquidity = state.liquidity;
        if (state.tick != _slot0.tick) {
            (slot0.sqrtPriceX96, slot0.tick) = (state.sqrtPriceX96, state.tick);
        }
        if (zeroForOne) {
            feeGrowthGlobal0X128 = state.feeGrowthGlobalX128;
        } else {
            feeGrowthGlobal1X128 = state.feeGrowthGlobalX128;
        }
        (amount0, amount1) = zeroForOne
            ? (
                int256(amountSpecified - state.amountSpecifiedRemaining),
                -int256(state.amountCalculated)
            )
            : (
                -int256(state.amountCalculated),
                int256(amountSpecified - state.amountSpecifiedRemaining)
            );
        if (zeroForOne) {
            IERC20(token1).transfer(recipient, uint256(state.amountCalculated));
            uint256 balance0before = balance0();
            IPandaswapSwapCallback(msg.sender).pandaswapSwapCallback(
                amount0,
                amount1,
                data
            );
            if (balance0before + uint256(amount0) < balance0())
                revert InsufficientInputAmount();
        } else {
            IERC20(token0).transfer(recipient, uint256(-amount0));
            uint256 balance1Before = balance1();
            IPandaswapSwapCallback(msg.sender).pandaswapSwapCallback(
                amount0,
                amount1,
                data
            );
            if (balance1Before + uint256(amount1) > balance1())
                revert InsufficientInputAmount();
        }

        emit Swap(
            msg.sender,
            recipient,
            amount0,
            amount1,
            slot0.sqrtPriceX96,
            liquidity,
            slot0.tick
        );
    }

    function increaseObservationCardinalityNext(
        uint16 observationCardinalityNext
    ) public {
        uint16 observationCardinalityNextOld = slot0.observationCardinalityNext;
        uint16 observationCardinalityNextNew = observations.grow(
            observationCardinalityNextOld,
            observationCardinalityNext
        );
        if (observationCardinalityNextNew != observationCardinalityNextOld) {
            slot0.observationCardinalityNext = observationCardinalityNext;
        }
        emit IncreaseObservationCardinalityNext(
            observationCardinalityNextOld,
            observationCardinalityNextNew
        );
    }

    function observe(
        uint32[] calldata secondsAgos
    ) public view returns (int56[] memory tickCumulatives) {
        return
            observations.observe(
                _blockTimestamp(),
                secondsAgos,
                slot0.tick,
                slot0.observationIndex,
                slot0.observationCardinality
            );
    }

    // //---------------------------------------------------------------------------
    // //============================== INTERNAL ===================================
    function _modifyPosition(
        ModifyPositionParams memory params
    )
        internal
        returns (Position.Info storage position, int256 amount0, int256 amount1)
    {
        //gas optimizations
        Slot0 memory _slot0 = slot0;
        uint256 _feeGrowthGlobal0X128 = feeGrowthGlobal0X128;
        uint256 _feeGrowthGlobal1X128 = feeGrowthGlobal1X128;

        position = positions.get(
            params.owner,
            params.lowerTick,
            params.upperTick
        );
        bool flippedLower = ticks.update(
            params.lowerTick,
            params.liquidityDelta,
            _slot0.tick,
            _feeGrowthGlobal0X128,
            _feeGrowthGlobal1X128,
            false
        );
        bool flippedUpper = ticks.update(
            params.upperTick,
            params.liquidityDelta,
            _slot0.tick,
            _feeGrowthGlobal0X128,
            _feeGrowthGlobal1X128,
            true
        );
        if (flippedLower) {
            tickBitmap.flipTick(params.lowerTick, int24(tickSpacing));
        }
        if (flippedUpper) {
            tickBitmap.flipTick(params.upperTick, int24(tickSpacing));
        }
        //get fee growth inside
        (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) = ticks
            .getFeeGrowthInside(
                params.lowerTick,
                params.upperTick,
                _slot0.tick,
                feeGrowthGlobal0X128,
                feeGrowthGlobal1X128
            );
        //update position
        position.update(
            params.liquidityDelta,
            feeGrowthInside0X128,
            feeGrowthInside1X128
        );
        if (_slot0.tick < params.lowerTick) {
            amount0 = int256(
                Math.calcAmount0Delta(
                    TickMath.getSqrtRatioAtTick(params.lowerTick),
                    TickMath.getSqrtRatioAtTick(params.upperTick),
                    (
                        params.liquidityDelta > 0
                            ? uint128(params.liquidityDelta)
                            : uint128(-params.liquidityDelta)
                    )
                )
            );
        } else if (_slot0.tick < params.upperTick) {
            amount0 = int256(
                Math.calcAmount0Delta(
                    _slot0.sqrtPriceX96,
                    TickMath.getSqrtRatioAtTick(params.upperTick),
                    (
                        params.liquidityDelta > 0
                            ? uint128(params.liquidityDelta)
                            : uint128(-params.liquidityDelta)
                    )
                )
            );

            amount1 = int256(
                Math.calcAmount1Delta(
                    TickMath.getSqrtRatioAtTick(params.lowerTick),
                    _slot0.sqrtPriceX96,
                    (
                        params.liquidityDelta > 0
                            ? uint128(params.liquidityDelta)
                            : uint128(-params.liquidityDelta)
                    )
                )
            );

            liquidity = LiquidityMath.addLiquidity(
                liquidity,
                params.liquidityDelta
            );
        } else {
            amount1 = int256(
                Math.calcAmount1Delta(
                    TickMath.getSqrtRatioAtTick(params.lowerTick),
                    TickMath.getSqrtRatioAtTick(params.upperTick),
                    (
                        params.liquidityDelta > 0
                            ? uint128(params.liquidityDelta)
                            : uint128(-params.liquidityDelta)
                    )
                )
            );
        }
    }

    function _blockTimestamp() internal view returns (uint32 timestamp) {
        timestamp = uint32(block.timestamp);
    }
}
