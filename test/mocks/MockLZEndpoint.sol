// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/// @dev Minimal mock: OFTUpgradeable's constructor/initialize typically won't call the endpoint in unit tests.
/// This exists purely to provide a non-zero endpoint address for versions that validate it.
contract MockLZEndpoint {
    fallback() external payable {}
    receive() external payable {}
}
