// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { DStockOFTUpgradeable } from "../src/DStockOFTUpgradeable.sol";

/// @notice Deploy DStockOFTUpgradeable (TransparentUpgradeableProxy):
/// - Deploy the implementation contract
/// - Deploy a TransparentUpgradeableProxy and call initialize via proxy constructor (delegatecall)
///
/// Environment variables (example):
/// - DEPLOYER_PK=...                 // private key used to broadcast txs
/// - LZ_ENDPOINT=0x...               // LayerZero EndpointV2 address
/// - NAME="DStock"                   // Token name
/// - SYMBOL="DST"                    // Token symbol
/// - LZ_DELEGATE=0x...               // LayerZero delegate (also becomes owner)
/// - ADMIN=0x...                     // AccessControl DEFAULT_ADMIN_ROLE
/// - TREASURY=0x...                  // optional; defaults to ADMIN if omitted
/// - PROXY_ADMIN_OWNER=0x...         // optional; owner of ProxyAdmin created by the proxy (defaults to ADMIN)
contract DeployDStockOFTUpgradeable is Script {
    // EIP-1967 admin slot = bytes32(uint256(keccak256("eip1967.proxy.admin")) - 1)
    bytes32 private constant _ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    function run() external {
        uint256 pk = vm.envUint("DEPLOYER_PK");

        address lzEndpoint = vm.envAddress("LZ_ENDPOINT");
        string memory name = vm.envString("NAME");
        string memory symbol = vm.envString("SYMBOL");
        address lzDelegate = vm.envAddress("LZ_DELEGATE");
        address admin = vm.envAddress("ADMIN");
        address treasury = vm.envOr("TREASURY", address(0));
        if (treasury == address(0)) treasury = admin;
        address proxyAdminOwner = vm.envOr("PROXY_ADMIN_OWNER", admin);

        vm.startBroadcast(pk);

        DStockOFTUpgradeable impl = new DStockOFTUpgradeable(lzEndpoint);
        bytes memory initData = abi.encodeCall(DStockOFTUpgradeable.initialize, (name, symbol, lzDelegate, admin, treasury));
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(impl), proxyAdminOwner, initData);

        vm.stopBroadcast();

        address proxyAdminAddr = address(uint160(uint256(vm.load(address(proxy), _ADMIN_SLOT))));
        console2.log("DStockOFTUpgradeable implementation:", address(impl));
        console2.log("DStockOFTUpgradeable proxy:", address(proxy));
        console2.log("ProxyAdmin:", proxyAdminAddr);
        console2.log("ProxyAdmin owner:", proxyAdminOwner);
        console2.log("owner (delegate):", DStockOFTUpgradeable(address(proxy)).owner());
        console2.log("admin:", admin);
        console2.log("treasury:", DStockOFTUpgradeable(address(proxy)).treasury());
    }
}


