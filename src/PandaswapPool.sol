// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./lib/Tick.sol";
import "./lib/Position.sol";
import './lib/TickBitmap.sol';
import "./interfaces/IPandaswapMintCallback.sol";
import "./interfaces/IPandaswapSwapCallback.sol";
import "./interfaces/IERC20.sol";
import "./lib/Math.sol";
import "./lib/TickMath.sol";
import './lib/SwapMath.sol';

contract PandaswapPool {
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

    error InvalidTickRange();
    error ZeroLiquidity();
    error InsufficientInputAmount();
    error NotEnoughLiquidity();

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
        Slot memory _slot= slot0;
        //Price range is above current price
        if(_slot0.tick<lowerTick){
            amount0=Math.calcAmount0Delta(TickMath.getSqrtRatioAtTick(lowerTick),TickMath.getSqrtRatioAtTick(upperTick),amount);
        }
        //Price range includes current price
        else if (_slot0<upperTick){
        bool flippedLower = ticks.update(lowerTick, amount);
        bool flippedUpper = ticks.update(upperTick, amount);
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
        Slot0 memory _slot0 = slot0;
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
        liquidity += uint128(amount);}
        //Price range is below current price
        else {
        amount1=Math.calcAmount1Delta(
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

    function swap(
        address recipient,
        bool zeroForOne,
        uint256 amountSpecified,
        bytes calldata data
    ) public returns (int256 amount0, int256 amount1) {
        Slot0 memory _slot0 = slot0;
        uint128 _liquidity = liquidity;
        SwapState memory state = SwapState({
            amountSpecifiedRemaining: amountSpecified,
            amountCalculated: 0,
            sqrtPriceX96: _slot0.sqrtPriceX96,
            tick: _slot0.tick,
            liquidity: _liquidity
        });
        while (state.amountSpecifiedRemaining > 0) {
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
                    step.sqrtPriceNextX96,
                    liquidity,
                    state.amountSpecifiedRemaining
                );
            state.amountSpecifiedRemaining -= step.amountIn;
            state.amountCalculated += step.amountOut;
            if (state.sqrtPriceX96=step.sqrtPriceNextX96) {
                int128 liquidityDelta=tick.cross(step.nextTick);
                if (zeroForOne) liquidityDelta=-liquidityDelta;
                state.liquidity= liquidityMath.addLiquidity(
                    state.liquidity,
                    liquidityDelta
                );
                if (state.liquidity==0) revert NotEnoughLiquidity(); // This check is not implemented in UniswapV3pool.sol
                state.tick=zeroForOne ? step.nextTick-1 : step.nextTick;          
            } else{
            state.tick = TickMath.getTickAtSqrtRatio(state.sqrtPriceX96); }
        }
        if (_liquidity != state.liquidity) liquidity=state.liquidity;
        if (state.tick != _slot0.tick) {
            (slot0.sqrtPriceX96, slot0.tick) = (state.sqrtPriceX96, state.tick);
        }
        (amount0,amount1)=zeroForOne
        ?(int256(amountSpecified-state.amountSpecifiedRemaining),-int256(state.amountCalculated))
        :(-int256(state.amountCalculated),int256(amountSpecified-state.amountSpecifiedRemaining));
        if(zeroForOne){
        IERC20(token1).transfer(recipient, uint256(state.amountCalculated));
        uint256 balance0before = balance0();
        IPandaswapSwapCallback(msg.sender).pandaswapSwapCallback(
            amount0,
            amount1,
            data
        );
        if (balance0before + uint256(amount0) < balance1()) revert InsufficientInputAmount();
        }else{
                IERC20(token0).transfer(recipient, uint256(-amount0));
                uint256 balance1Before=balance1();
                IPandaswapSwapCallback(msg.sender).pandaswapSwapCallback(
                    amount0,
                    amount1,
                    data
                );
                if(balance1Before+uint256(amount1)>balance1())revert InsufficientInputAmount();
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
