// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import { OFTUpgradeable } from "@layerzerolabs/oft-evm-upgradeable/contracts/oft/OFTUpgradeable.sol";
/**
 * @title DStockOFTUpgradeable (Transparent Proxy + Compliance/Ops Controls)
 *
 * Upgrade model: TransparentUpgradeableProxy + ProxyAdmin
 * - Upgrades are performed by ProxyAdmin (owner-controlled)
 */
contract DStockOFTUpgradeable is
    Initializable,
    OFTUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable
{
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");
    bytes32 public constant BLACKLIST_MANAGER_ROLE = keccak256("BLACKLIST_MANAGER_ROLE");
    bytes32 public constant CONFISCATOR_ROLE = keccak256("CONFISCATOR_ROLE");
    // NOTE: Upgrades are controlled by ProxyAdmin. The implementation does not expose an upgrade role.

    mapping(address => bool) public blackList;
    address public treasury;
    bool public interceptCreditToTreasury;

    event BlackListUpdated(address indexed user, bool isBlackListed);
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event FundsConfiscated(address indexed from, address indexed to, uint256 amount);
    event CrossChainInterception(address indexed intendedRecipient, address indexed actualRecipient, uint256 amount);
    event InterceptCreditModeChanged(bool enabled);

    error BlackListed(address user);
    error NotBlackListed(address user);
    error InvalidAddress(address addr);
    error AmountExceedsBalance(uint256 balance, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address _lzEndpoint) OFTUpgradeable(_lzEndpoint) {
        _disableInitializers();
    }

    function initialize(
        string memory _name,
        string memory _symbol,
        address _lzDelegate,
        address _admin,
        address _treasury
    ) external initializer {
        __OFT_init(_name, _symbol, _lzDelegate);

        // Compatibility: some LayerZero OFTUpgradeable variants do not initialize Ownable.
        if (owner() == address(0)) {
            _transferOwnership(_lzDelegate);
        }

        __AccessControl_init();
        __Pausable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(PAUSER_ROLE, _admin);
        _grantRole(UNPAUSER_ROLE, _admin);
        _grantRole(BLACKLIST_MANAGER_ROLE, _admin);
        _grantRole(CONFISCATOR_ROLE, _admin);

        interceptCreditToTreasury = true;
        emit InterceptCreditModeChanged(true);

        address t = _treasury == address(0) ? _admin : _treasury;
        if (t == address(0)) revert InvalidAddress(t);
        treasury = t;
        emit TreasuryUpdated(address(0), t);
    }

    // ==================== Pause ====================
    function pauseBridge() external onlyRole(PAUSER_ROLE) { _pause(); }
    function unpauseBridge() external onlyRole(UNPAUSER_ROLE) { _unpause(); }

    // ==================== Config ====================
    function setTreasury(address _treasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_treasury == address(0)) revert InvalidAddress(_treasury);
        if (blackList[_treasury]) revert BlackListed(_treasury);
        address old = treasury;
        treasury = _treasury;
        emit TreasuryUpdated(old, _treasury);
    }

    function setInterceptCreditToTreasury(bool _enabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        interceptCreditToTreasury = _enabled;
        emit InterceptCreditModeChanged(_enabled);
    }

    // ==================== Blacklist ====================
    function updateBlackList(address _user, bool _isBlackListed) external onlyRole(BLACKLIST_MANAGER_ROLE) {
        if (_user == address(0)) revert InvalidAddress(_user);
        if (_user == address(this)) revert InvalidAddress(_user);
        if (_user == owner()) revert InvalidAddress(_user);
        if (_user == treasury) revert InvalidAddress(_user);
        if (hasRole(DEFAULT_ADMIN_ROLE, _user)) revert InvalidAddress(_user);

        blackList[_user] = _isBlackListed;
        emit BlackListUpdated(_user, _isBlackListed);
    }

    // ==================== Confiscation ====================
    function confiscateBlacklistedFunds(address _from, address _to, uint256 _amount)
        external
        onlyRole(CONFISCATOR_ROLE)
    {
        if (!blackList[_from]) revert NotBlackListed(_from);

        address recipient = _to == address(0) ? treasury : _to;
        if (recipient == address(0)) revert InvalidAddress(recipient);
        if (blackList[recipient]) revert BlackListed(recipient);

        uint256 bal = balanceOf(_from);
        uint256 amount = _amount == 0 ? bal : _amount;
        if (amount > bal) revert AmountExceedsBalance(bal, amount);

        blackList[_from] = false;
        _transfer(_from, recipient, amount);
        blackList[_from] = true;

        emit FundsConfiscated(_from, recipient, amount);
    }

    // ==================== Core enforcement ====================
    function _update(address _from, address _to, uint256 _amount) internal virtual override {
        if (_from != address(0) && blackList[_from]) revert BlackListed(_from);
        if (_to != address(0) && blackList[_to]) revert BlackListed(_to);
        super._update(_from, _to, _amount);
    }

    function _debit(
        address _from,
        uint256 _amountLD,
        uint256 _minAmountLD,
        uint32 _dstEid
    )
        internal
        virtual
        override
        whenNotPaused
        returns (uint256 amountSentLD, uint256 amountReceivedLD)
    {
        if (blackList[_from]) revert BlackListed(_from);
        return super._debit(_from, _amountLD, _minAmountLD, _dstEid);
    }

    function _credit(
        address _to,
        uint256 _amountLD,
        uint32 _srcEid
    )
        internal
        virtual
        override
        whenNotPaused
        returns (uint256 amountReceivedLD)
    {
        if (blackList[_to]) {
            if (!interceptCreditToTreasury) revert BlackListed(_to);

            address actual = treasury;
            if (actual == address(0)) revert InvalidAddress(actual);
            if (blackList[actual]) revert BlackListed(actual);

            emit CrossChainInterception(_to, actual, _amountLD);
            return super._credit(actual, _amountLD, _srcEid);
        }

        return super._credit(_to, _amountLD, _srcEid);
    }

    uint256[44] private __gap;
}
