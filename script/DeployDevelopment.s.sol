// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../test/ERC20Mintable.sol";
import "../src/PandaswapPool.sol";
import "../src/PandaswapManager.sol";
import "../src/interfaces/IPandaswapPoolDeployer.sol";

contract DeployDevelopment is Script, IPandaswapPoolDeployer {
    PoolParameters public parameters;

    function setUp() public {}

    function run() public {
        uint256 wethBalance = 1 ether;
        uint256 usdcBalance = 5042 ether;
        int24 currentTick = 85176;
        uint160 currentSqrtP = 5602277097478614198912276234240;
        vm.startBroadcast();
        ERC20Mintable token0 = new ERC20Mintable("Wrapped Ether", "WETH", 18);
        ERC20Mintable token1 = new ERC20Mintable("USD Coin", "USDC", 18);
        parameters = PoolParameters({
            factory: address(this),
            token0: address(token0),
            token1: address(token1),
            tickSpacing: 1
        });
        PandaswapPool pool = new PandaswapPool();
        PandaswapManager manager = new PandaswapManager(address(this));
        token0.mint(msg.sender, wethBalance);
        token1.mint(msg.sender, usdcBalance);
        vm.stopBroadcast();
        console.log("WETH address:", address(token0));
        console.log("USDC address:", address(token1));
        console.log("Pool address:", address(pool));
        console.log("Manager address:", address(manager));
    }
}
