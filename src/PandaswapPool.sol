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

contract PandaswapPool is Test {
    using Tick for mapping(int24 => Tick.Info);
    using Position for mapping(bytes32 => Position.Info);
    using Position for Position.Info;
    using TickBitmap for mapping(int16 => uint256);

    int24 internal constant MIN_TICK = -887272;
    int24 internal constant MAX_TICK = -MIN_TICK;

    //Pool tokens, immutable
    address public immutable token0;
    address public immutable token1;

    //Packing variables that are read together
    struct Slot0 {
        // Current sqrt(P)
        uint160 sqrtPriceX96;
        // Current tick
        int24 tick;
    }
    Slot0 public slot0;
    struct CallbackData {
        address token0;
        address token1;
        address payer;
    }
    struct SwapState {
        uint256 amountSpecifiedRemaining;
        uint256 amountCalculated;
        uint160 sqrtPriceX96;
        int24 tick;
        uint128 liquidity;
    }
    struct StepState {
        uint160 sqrtPriceStartX96;
        int24 nextTick;
        uint160 sqrtPriceNextX96;
        uint256 amountIn;
        uint256 amountOut;
    }

    //Amount of liquidity, L.
    uint128 public liquidity;

    //Ticks info
    mapping(int24 => Tick.Info) public ticks;
    //Positions info
    mapping(bytes32 => Position.Info) public positions;
    //TickBitmap
    mapping(int16 => uint256) public tickBitmap;

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
    event Flash(address sender, uint256 amount0, uint256 amount1);

    error InvalidTickRange();
    error ZeroLiquidity();
    error InsufficientInputAmount();
    error NotEnoughLiquidity();
    error InvalidPriceLimit();

    constructor(
        address _token0,
        address _token1,
        uint160 _sqrtPriceX96,
        int24 _tick
    ) {
        token0 = _token0;
        token1 = _token1;

        slot0 = Slot0({sqrtPriceX96: _sqrtPriceX96, tick: _tick});
    }

    /// @notice Adds liquidity for the given owner/lowerTick/upperTick/amount of liquidity
    /// @dev Explain to a developer any extra details

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
        bool flippedLower = ticks.update(lowerTick, int128(amount), false);
        bool flippedUpper = ticks.update(upperTick, int128(amount), true);
        if (flippedLower) {
            tickBitmap.flipTick(lowerTick, 1);
        }
        if (flippedUpper) {
            tickBitmap.flipTick(upperTick, 1);
        }
        Position.Info storage position = positions.get(
            owner,
            lowerTick,
            upperTick
        );
        position.update(amount);
        //Get current slot0
        Slot0 memory _slot0 = slot0;
        //Price range is above current price
        if (_slot0.tick < lowerTick) {
            amount0 = Math.calcAmount0Delta(
                TickMath.getSqrtRatioAtTick(lowerTick),
                TickMath.getSqrtRatioAtTick(upperTick),
                amount
            );
        }
        //Price range includes current price
        else if (_slot0.tick < upperTick) {
            amount0 = Math.calcAmount0Delta(
                _slot0.sqrtPriceX96,
                TickMath.getSqrtRatioAtTick(upperTick),
                amount
            );
            amount1 = Math.calcAmount1Delta(
                _slot0.sqrtPriceX96,
                TickMath.getSqrtRatioAtTick(lowerTick),
                amount
            );
            liquidity += uint128(amount);
        }
        //Price range is below current price
        else {
            amount1 = Math.calcAmount1Delta(
                TickMath.getSqrtRatioAtTick(lowerTick),
                TickMath.getSqrtRatioAtTick(upperTick),
                amount
            );
        }
        uint256 balance0Before;
        uint256 balance1Before;
        if (amount0 > 0) balance0Before = balance0();
        if (amount1 > 0) balance1Before = balance1();
        IPandaswapMintCallback(msg.sender).pandaswapMintCallback(
            amount0,
            amount1,
            data
        );
        if (amount0 > 0 && balance0Before + amount0 > balance0())
            revert InsufficientInputAmount();
        if (amount1 > 0 && balance1Before + amount1 > balance1())
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
        uint256 balance0Before = IERC20(token0).balanceOf(address(this));
        uint256 balance1Before = IERC20(token1).balanceOf(address(this));
        if (amount0 > 0) IERC20(token0).transfer(msg.sender, amount0);
        if (amount1 > 0) IERC20(token1).transfer(msg.sender, amount1);
        IPandaswapFlashCallback(msg.sender).pandaswapFlashCallback(data);
        require(IERC20(token0).balanceOf(address(this)) >= balance0Before);
        require(IERC20(token1).balanceOf(address(this)) >= balance1Before);
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
            liquidity: liquidity
        });
        console.log("current tick", uint24(_slot0.tick));
        console.log("looping swap..."); //for testing purpose
        console.log("current liquidity", _liquidity);
        while (
            state.amountSpecifiedRemaining > 0 &&
            state.sqrtPriceX96 != sqrtPriceLimitX96
        ) {
            StepState memory step;
            (step.nextTick, ) = tickBitmap.nextInitializedTickWithinOneWord(
                state.tick,
                1,
                zeroForOne
            );
            step.sqrtPriceNextX96 = TickMath.getSqrtRatioAtTick(step.nextTick);
            (state.sqrtPriceX96, step.amountIn, step.amountOut) = SwapMath
                .computeSwapStep(
                    state.sqrtPriceX96,
                    (
                        zeroForOne
                            ? step.sqrtPriceNextX96 < sqrtPriceLimitX96
                            : step.sqrtPriceNextX96 > sqrtPriceLimitX96
                    )
                        ? sqrtPriceLimitX96
                        : step.sqrtPriceNextX96,
                    liquidity,
                    state.amountSpecifiedRemaining
                );
            console.log("step nextTick:", uint24(step.nextTick));
            console.log("step amountIn:", step.amountIn);
            state.amountSpecifiedRemaining -= step.amountIn;
            console.log(
                "amountSpecifiedRemaining:",
                state.amountSpecifiedRemaining
            );
            state.amountCalculated += step.amountOut;
            console.log("amountCalculated:", state.amountCalculated);
            if (state.sqrtPriceX96 == step.sqrtPriceNextX96) {
                int128 liquidityDelta = ticks.cross(step.nextTick);
                if (liquidityDelta < 0) {
                    console.log("liquidity Delta: -", uint128(-liquidityDelta));
                }

                if (zeroForOne) liquidityDelta = -liquidityDelta;
                state.liquidity = LiquidityMath.addLiquidity(
                    state.liquidity,
                    liquidityDelta
                );
                console.log("liquidity updated to:", state.liquidity);
                if (state.liquidity == 0) revert NotEnoughLiquidity(); // This check is not implemented in UniswapV3pool.sol
                state.tick = zeroForOne ? step.nextTick - 1 : step.nextTick;
            } else {
                state.tick = TickMath.getTickAtSqrtRatio(state.sqrtPriceX96);
            }
        }
        if (_liquidity != state.liquidity) liquidity = state.liquidity;
        if (state.tick != _slot0.tick) {
            (slot0.sqrtPriceX96, slot0.tick) = (state.sqrtPriceX96, state.tick);
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
}
