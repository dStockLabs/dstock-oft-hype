// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import { DStockOFTAdapter } from "../src/DStockOFTAdapter.sol";

/// @notice Deploy DStockOFTAdapter (adapt an existing ERC20 into an OFTAdapter)
///
/// Environment variables (example):
/// - DEPLOYER_PK=...                 // private key used to broadcast txs
/// - TOKEN=0x...                     // underlying ERC20 address
/// - LZ_ENDPOINT=0x...               // LayerZero EndpointV2 address
/// - LZ_DELEGATE=0x...               // LayerZero delegate (also becomes owner)
contract DeployDStockOFTAdapter is Script {
    function run() external {
        uint256 pk = vm.envUint("DEPLOYER_PK");

        address token = vm.envAddress("TOKEN");
        address lzEndpoint = vm.envAddress("LZ_ENDPOINT");
        address lzDelegate = vm.envAddress("LZ_DELEGATE");

        vm.startBroadcast(pk);
        DStockOFTAdapter adapter = new DStockOFTAdapter(token, lzEndpoint, lzDelegate);
        vm.stopBroadcast();

        console2.log("DStockOFTAdapter:", address(adapter));
        console2.log("inner token:", token);
        console2.log("owner (delegate):", adapter.owner());
    }
}


