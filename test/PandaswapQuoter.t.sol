//SPDX-License-Identifier:MIT
pragma solidity ^0.8.14;

import "forge-std/Test.sol";
import "./TestUtils.sol";
import "./ERC20Mintable.sol";
import "../src/PandaswapFactory.sol";
import "../src/PandaswapPool.sol";
import "../src/PandaswapQuoter.sol";

contract PandaswapQuoterTest is Test, TestUtils {
    ERC20Mintable weth;
    ERC20Mintable usdc;
    ERC20Mintable panda;
    PandaswapFactory factory;
    PandaswapManager manager;
    PandaswapPool pool;
    PandaswapQuoter quoter;

    function setUp() public {
        usdc = new ERC20Mintable("USDC", "USDC", 18);
        weth = new ERC20Mintable("Ether", "ETH", 18);
        panda = new ERC20Mintable("Panda Coin", "Panda", 18);
        factory = new PandaswapFactory();
        manager = new PandaswapManager(address(factory));
        uint256 wethBalance = 100 ether;
        uint256 usdcBalance = 1000000 ether;
        uint256 pandaBalance = 1000 ether;
        weth.mint(address(this), wethBalance);
        usdc.mint(address(this), usdcBalance);
        panda.mint(address(this), pandaBalance);
        //Deploy pool contracts: weth/usdc, weth/panda
        PandaswapPool poolUSDC = PandaswapPool(
            factory.createPool(address(weth), address(usdc), 60)
        );
        poolUSDC.initialize(sqrtP(5000));
        PandaswapPool poolPanda = PandaswapPool(
            factory.createPool(address(weth), address(panda), 60)
        );
        poolPanda.initialize(sqrtP(10));
        weth.approve(address(manager), wethBalance);
        usdc.approve(address(manager), usdcBalance);
        panda.approve(address(manager), pandaBalance);
        //Mint positions in both pools
        manager.mint(
            mintParams60(
                address(weth),
                address(usdc),
                4545,
                5500,
                1 ether,
                5000 ether
            )
        );
        manager.mint(
            mintParams60(
                address(weth),
                address(panda),
                7,
                13,
                10 ether,
                100 ether
            )
        );
        quoter = new PandaswapQuoter(address(factory));
    }

    function testQuoteETHforUSDC() public {
        (uint256 amountOut, uint160 sqrtPriceX96After, int24 tickAfter) = quoter
            .quoteSingle(
                PandaswapQuoter.QuoteSingleParams({
                    tokenIn: address(weth),
                    tokenOut: address(usdc),
                    tickSpacing: 60,
                    amountIn: 0.01337 ether,
                    sqrtPriceLimitX96: sqrtP(4993)
                })
            );
        assertEq(amountOut, 66.809153442256308009 ether, "invalid amountOut");
        assertEq(
            sqrtPriceX96After,
            5598854004958668990019104567840,
            "invalid sqrtPriceX96After"
        );
        assertEq(tickAfter, 85163, "invalid tickAfter");
    }

    function testQuoteUSDCforETH() public {
        (uint256 amountOut, uint160 sqrtPriceX96After, int24 tickAfter) = quoter
            .quoteSingle(
                PandaswapQuoter.QuoteSingleParams({
                    tokenIn: address(usdc),
                    tokenOut: address(weth),
                    tickSpacing: 60,
                    amountIn: 42 ether,
                    sqrtPriceLimitX96: sqrtP(5005)
                })
            );
        assertEq(amountOut, 0.008396774627565324 ether, "invalid amountOut");
        assertEq(
            sqrtPriceX96After,
            5604429046402228950611610935846, // 5003.841941749589
            "invalid sqrtPriceX96After"
        );
        assertEq(tickAfter, 85183, "invalid tickAFter");
    }

    /**
     * Panda->ETH->USDC
     */
    function testQuotePandaforUSDCviaEth() public {
        bytes memory path = bytes.concat(
            bytes20(address(panda)),
            bytes3(uint24(60)),
            bytes20(address(weth)),
            bytes3(uint24(60)),
            bytes20(address(usdc))
        );
        (
            uint256 amountOut,
            uint160[] memory sqrtPriceX96AfterList,
            int24[] memory tickAfterList
        ) = quoter.quote(path, 3 ether);
        assertEq(amountOut, 1472.545906750265420689 ether, "invalid amountOut");
        assertEq(
            sqrtPriceX96AfterList[0],
            251775459842086338964181233032,
            "invalid sqrtPriceX96After"
        );
        assertEq(
            sqrtPriceX96AfterList[1],
            5526828440835641442318026170540,
            "invalid sqrtPriceX96After"
        );
        assertEq(tickAfterList[0], 23125, "invalid tickAFter");
        assertEq(tickAfterList[1], 84904, "invalid tickAFter");
    }
}
