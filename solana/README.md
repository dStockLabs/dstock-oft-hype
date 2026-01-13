# Solana (Anchor) — OFT programs

This folder contains the **Solana** implementation of the OFT programs (Anchor workspace).

## Layout

- `Anchor.toml`: Anchor workspace config
- `Cargo.toml` / `Cargo.lock`: Rust workspace
- `programs/oft`: OFT program
- `programs/endpoint-mock`: endpoint mock used for local testing/dev

## Build

```bash
cd solana
anchor build
```

## Notes

- `Anchor.toml` in this repo is copied from the source workspace; if it references a local wallet file that you don't want to commit, update:
  - `provider.wallet` to your local keypair (commonly `~/.config/solana/id.json`)

