// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Test.sol";

import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { ITransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import { DStockOFTUpgradeable } from "../src/DStockOFTUpgradeable.sol";
import { MockLZEndpoint } from "./mocks/MockLZEndpoint.sol";

/// @dev Test helper: expose mint / burn / _debit / _credit for unit tests.
contract DStockOFTUpgradeableTestable is DStockOFTUpgradeable {
    constructor(address _lzEndpoint) DStockOFTUpgradeable(_lzEndpoint) {}

    function mintTest(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burnTest(address from, uint256 amount) external {
        _burn(from, amount);
    }

    function exposedDebit(address from, uint256 amountLD, uint256 minAmountLD, uint32 dstEid)
        external
        returns (uint256 amountSentLD, uint256 amountReceivedLD)
    {
        return _debit(from, amountLD, minAmountLD, dstEid);
    }

    function exposedCredit(address to, uint256 amountLD, uint32 srcEid)
        external
        returns (uint256 amountReceivedLD)
    {
        return _credit(to, amountLD, srcEid);
    }
}

/// @dev Upgrade test helper: V2 adds a new function to prove the implementation was upgraded.
contract DStockOFTUpgradeableTestableV2 is DStockOFTUpgradeableTestable {
    constructor(address _lzEndpoint) DStockOFTUpgradeableTestable(_lzEndpoint) {}

    function version() external pure returns (uint256) {
        return 2;
    }
}

contract DStockOFTUpgradeableTest is Test {
    // actors
    address admin    = makeAddr("admin");
    address delegate = makeAddr("lzDelegate");
    address treasury = makeAddr("treasury");
    address alice    = makeAddr("alice");
    address bob      = makeAddr("bob");
    address pauser   = makeAddr("pauser");
    address unpauser = makeAddr("unpauser");
    address proxyAdminOwner = makeAddr("proxyAdminOwner");

    // system
    MockLZEndpoint endpoint;
    DStockOFTUpgradeableTestable implV1;
    DStockOFTUpgradeableTestable token; // proxy as token
    ProxyAdmin proxyAdmin;

    // EIP-1967 admin slot = bytes32(uint256(keccak256("eip1967.proxy.admin")) - 1)
    bytes32 private constant _ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    uint32 constant DST_EID = 30111;
    uint32 constant SRC_EID = 30112;

    function setUp() external {
        endpoint = new MockLZEndpoint();

        // deploy implementation
        implV1 = new DStockOFTUpgradeableTestable(address(endpoint));

        // init data for proxy
        bytes memory initData = abi.encodeCall(
            DStockOFTUpgradeable.initialize,
            ("DStock", "DST", delegate, admin, treasury)
        );

        // deploy transparent proxy (auto-deploys ProxyAdmin internally)
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(implV1), proxyAdminOwner, initData);
        token = DStockOFTUpgradeableTestable(address(proxy));

        // discover ProxyAdmin address from EIP-1967 admin slot
        address proxyAdminAddr = address(uint160(uint256(vm.load(address(proxy), _ADMIN_SLOT))));
        proxyAdmin = ProxyAdmin(proxyAdminAddr);

        // role separation (optional but good for tests)
        vm.startPrank(admin);
        token.grantRole(token.PAUSER_ROLE(), pauser);
        token.grantRole(token.UNPAUSER_ROLE(), unpauser);

        // Important: initialize grants all roles to `admin` by default.
        // For role-separation tests, revoke roles from `admin`.
        token.revokeRole(token.PAUSER_ROLE(), admin);
        token.revokeRole(token.UNPAUSER_ROLE(), admin);
        vm.stopPrank();
    }

    // =============================================================
    // Initialize
    // =============================================================
    function test_initialize_setsTreasuryAndMode() external {
        assertEq(token.treasury(), treasury);
        assertTrue(token.interceptCreditToTreasury()); // default true

        // owner is the LZ delegate in most OFTUpgradeable implementations
        assertEq(token.owner(), delegate);

        // admin has DEFAULT_ADMIN_ROLE
        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), admin));
    }

    function test_initialize_reverts_ifAdminIsZero_evenIfTreasuryNonZero() external {
        bytes memory initData = abi.encodeCall(
            DStockOFTUpgradeable.initialize,
            ("DStock", "DST", delegate, address(0), treasury)
        );

        vm.expectRevert(abi.encodeWithSelector(DStockOFTUpgradeable.InvalidAddress.selector, address(0)));
        new TransparentUpgradeableProxy(address(implV1), proxyAdminOwner, initData);
    }

    // =============================================================
    // Pause / Unpause (cross-chain only)
    // =============================================================
    function test_pause_blocksDebitAndCredit_onlyCrossChain() external {
        // mint some to alice for debit test
        token.mintTest(alice, 1_000e18);

        // pause by pauser
        vm.prank(pauser);
        token.pauseBridge();

        // debit should revert
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        vm.prank(alice);
        token.exposedDebit(alice, 100e18, 100e18, DST_EID);

        // credit should revert
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        token.exposedCredit(bob, 10e18, SRC_EID);

        // local transfer still works (not paused), assuming no blacklist
        vm.prank(alice);
        token.transfer(bob, 1e18);
        assertEq(token.balanceOf(bob), 1e18);

        // unpause by unpauser
        vm.prank(unpauser);
        token.unpauseBridge();

        // now debit works
        vm.prank(alice);
        (uint256 sent, uint256 received) = token.exposedDebit(alice, 10e18, 10e18, DST_EID);
        assertEq(sent, 10e18);
        assertEq(received, 10e18);
    }

    // =============================================================
    // Blacklist management restrictions
    // =============================================================
    function test_blacklist_cannotBlacklistCriticalAddresses() external {
        // cannot blacklist contract itself
        vm.startPrank(admin);
        // admin has BLACKLIST_MANAGER_ROLE by default from initialize
        vm.expectRevert(abi.encodeWithSelector(DStockOFTUpgradeable.InvalidAddress.selector, address(token)));
        token.updateBlackList(address(token), true);

        // cannot blacklist owner(delegate)
        vm.expectRevert(abi.encodeWithSelector(DStockOFTUpgradeable.InvalidAddress.selector, delegate));
        token.updateBlackList(delegate, true);

        // cannot blacklist treasury
        vm.expectRevert(abi.encodeWithSelector(DStockOFTUpgradeable.InvalidAddress.selector, treasury));
        token.updateBlackList(treasury, true);

        // cannot blacklist any DEFAULT_ADMIN_ROLE holder
        vm.expectRevert(abi.encodeWithSelector(DStockOFTUpgradeable.InvalidAddress.selector, admin));
        token.updateBlackList(admin, true);
        vm.stopPrank();
    }

    function test_blacklist_update_normalUser_ok() external {
        vm.prank(admin);
        token.updateBlackList(alice, true);
        assertTrue(token.blackList(alice));

        vm.prank(admin);
        token.updateBlackList(alice, false);
        assertFalse(token.blackList(alice));
    }

    // =============================================================
    // _update enforcement: transfer + mint/burn
    // =============================================================
    function test_blacklist_blocksLocalTransfer() external {
        token.mintTest(alice, 100e18);

        vm.prank(admin);
        token.updateBlackList(alice, true);

        vm.expectRevert(abi.encodeWithSelector(DStockOFTUpgradeable.BlackListed.selector, alice));
        vm.prank(alice);
        token.transfer(bob, 1e18);
    }

    function test_blacklist_blocksMintToBlacklisted_andBurnFromBlacklisted() external {
        // blacklist bob first
        vm.prank(admin);
        token.updateBlackList(bob, true);

        // mint to blacklisted should revert via _update(to blacklisted)
        vm.expectRevert(abi.encodeWithSelector(DStockOFTUpgradeable.BlackListed.selector, bob));
        token.mintTest(bob, 1e18);

        // to test burn-from-blacklisted, mint to bob before blacklisting
        vm.prank(admin);
        token.updateBlackList(bob, false);
        token.mintTest(bob, 10e18);

        vm.prank(admin);
        token.updateBlackList(bob, true);

        vm.expectRevert(abi.encodeWithSelector(DStockOFTUpgradeable.BlackListed.selector, bob));
        token.burnTest(bob, 1e18);
    }

    // =============================================================
    // Cross-chain credit interception mode
    // =============================================================
    function test_credit_blacklisted_interceptsToTreasury_byDefault() external {
        // blacklist bob
        vm.prank(admin);
        token.updateBlackList(bob, true);

        // credit to bob should go to treasury
        uint256 beforeTreasury = token.balanceOf(treasury);

        token.exposedCredit(bob, 5e18, SRC_EID);

        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(treasury), beforeTreasury + 5e18);
    }

    function test_credit_blacklisted_reverts_whenModeOff() external {
        // blacklist bob
        vm.prank(admin);
        token.updateBlackList(bob, true);

        // turn off interception
        vm.prank(admin);
        token.setInterceptCreditToTreasury(false);

        vm.expectRevert(abi.encodeWithSelector(DStockOFTUpgradeable.BlackListed.selector, bob));
        token.exposedCredit(bob, 1e18, SRC_EID);
    }

    // =============================================================
    // Cross-chain debit blacklist
    // =============================================================
    function test_debit_reverts_ifFromBlacklisted() external {
        token.mintTest(alice, 100e18);

        vm.prank(admin);
        token.updateBlackList(alice, true);

        vm.expectRevert(abi.encodeWithSelector(DStockOFTUpgradeable.BlackListed.selector, alice));
        vm.prank(alice);
        token.exposedDebit(alice, 10e18, 10e18, DST_EID);
    }

    // =============================================================
    // Confiscation
    // =============================================================
    function test_confiscate_fullBalance_toTreasury_whenToIsZero_andKeepsBlacklisted() external {
        // mint then blacklist
        token.mintTest(alice, 77e18);
        vm.prank(admin);
        token.updateBlackList(alice, true);

        uint256 beforeTreasury = token.balanceOf(treasury);

        // confiscate: _to=0 => treasury, _amount=0 => full balance
        vm.prank(admin); // admin has CONFISCATOR_ROLE by default
        token.confiscateBlacklistedFunds(alice, address(0), 0);

        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(treasury), beforeTreasury + 77e18);
        assertTrue(token.blackList(alice)); // restored
    }

    function test_confiscate_partial_toCustomRecipient() external {
        address custodian = makeAddr("custodian");

        token.mintTest(alice, 100e18);
        vm.prank(admin);
        token.updateBlackList(alice, true);

        vm.prank(admin);
        token.confiscateBlacklistedFunds(alice, custodian, 30e18);

        assertEq(token.balanceOf(custodian), 30e18);
        assertEq(token.balanceOf(alice), 70e18);
        assertTrue(token.blackList(alice));
    }

    function test_confiscate_reverts_ifAmountExceedsBalance() external {
        token.mintTest(alice, 10e18);
        vm.prank(admin);
        token.updateBlackList(alice, true);

        vm.expectRevert(abi.encodeWithSelector(DStockOFTUpgradeable.AmountExceedsBalance.selector, 10e18, 11e18));
        vm.prank(admin);
        token.confiscateBlacklistedFunds(alice, bob, 11e18);
    }

    // =============================================================
    // Transparent proxy upgrade (ProxyAdmin)
    // =============================================================
    function test_upgrade_onlyProxyAdminOwner() external {
        // deploy v2 implementation
        DStockOFTUpgradeableTestableV2 implV2 = new DStockOFTUpgradeableTestableV2(address(endpoint));

        // non-owner cannot upgrade ProxyAdmin
        vm.expectRevert();
        vm.prank(admin);
        proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(address(token)), address(implV2), "");

        // proxy admin owner can upgrade
        vm.prank(proxyAdminOwner);
        proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(address(token)), address(implV2), "");

        // call new function through proxy
        uint256 v = DStockOFTUpgradeableTestableV2(address(token)).version();
        assertEq(v, 2);
    }
}
