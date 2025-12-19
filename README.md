# dstock-oft

This repository uses **Foundry** and contains two contracts:


- `DStockOFTUpgradeable`: an OFT token implementation (built on LayerZero `OFTUpgradeable`) **designed to be deployed behind an OpenZeppelin `TransparentUpgradeableProxy`**. Upgrades are performed via the proxy’s `ProxyAdmin` (owner-controlled). The implementation itself does **not** expose UUPS upgrade functions. Features: blacklist, bridge pause (cross-chain only), confiscation, and blacklisted-credit interception.
- `DStockOFTAdapter`: an **OFTAdapter** for an *existing ERC20* (for cross-chain compatibility of legacy ERC20s)

## Build

```bash
forge build
```

## Test

> If `forge test` crashes on your machine (especially on macOS) due to reqwest/system proxy related panics, use `--offline`.

```bash
forge test --offline
```

## Contract Deployment

### Deploy `DStockOFTUpgradeable` (TransparentUpgradeableProxy: implementation + proxy + initialize)

Script: `script/DeployDStockOFTUpgradeable.s.sol`

Environment variables (see `env.example`):

- `DEPLOYER_PK`: deployer private key
- `LZ_ENDPOINT`: LayerZero EndpointV2 address
- `NAME`: token name
- `SYMBOL`: token symbol
- `LZ_DELEGATE`: LayerZero delegate (will also become `owner()`)
- `ADMIN`: AccessControl `DEFAULT_ADMIN_ROLE`
- `TREASURY`: optional; defaults to `ADMIN` if omitted
- `PROXY_ADMIN_OWNER`: optional; owner of the ProxyAdmin created by the proxy (defaults to `ADMIN`)

Run:

```bash
forge script script/DeployDStockOFTUpgradeable.s.sol:DeployDStockOFTUpgradeable \
  --rpc-url "$RPC_URL" \
  --broadcast
```

### Deploy `DStockOFTAdapter` (existing ERC20 -> OFTAdapter)

Script: `script/DeployDStockOFTAdapter.s.sol`

Environment variables:

- `DEPLOYER_PK`: deployer private key
- `TOKEN`: underlying ERC20 address to be adapted
- `LZ_ENDPOINT`: LayerZero EndpointV2 address
- `LZ_DELEGATE`: LayerZero delegate (will also become `owner()`)

Run:

```bash
forge script script/DeployDStockOFTAdapter.s.sol:DeployDStockOFTAdapter \
  --rpc-url "$RPC_URL" \
  --broadcast
```
