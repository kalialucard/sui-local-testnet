# sui-local-testnet 🌊

> Private single-validator Sui network in Docker — JSON-RPC endpoint and faucet in one command. Perfect for Move development and security research PoCs.

[![Sui](https://img.shields.io/badge/Sui-1.81.0-4DA2FF)](https://sui.io/)
[![Docker](https://img.shields.io/badge/Docker-Compose-blue?logo=docker)](https://www.docker.com/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

## What It Does

Spinning up a Sui testnet normally requires syncing from the network. This repo gives you a fully isolated, single-validator Sui chain in Docker with:

| Service | Endpoint |
|---------|----------|
| **JSON-RPC** | `http://127.0.0.1:9000` |
| **Faucet** | `http://127.0.0.1:9123` |

State is disposable — `docker compose down -v` wipes everything cleanly.

> Verified 2026-09-30 with `mysten/sui-tools:testnet` (sui 1.81.0-bf0c491c17b8). Pin an exact image tag for reproducible builds.

## Screenshot

<!-- TODO: add a screenshot of `sui client objects` output here -->
![Sui local testnet](docs/screenshot.png)

## Prerequisites

- Linux with Docker + Docker Compose v2
- `curl`
- Ports `9000` and `9123` free

## Quick Start

```bash
git clone https://github.com/kalialucard/sui-local-testnet.git
cd sui-local-testnet

docker compose up -d
# Wait ~10s for the validator to produce blocks
```

## Wallet Setup

```bash
# Create a new Sui address
sui client new-address ed25519

# Point the CLI at your local node
sui client switch --env localnet
```

## Faucet

```bash
SUI_ADDRESS=$(sui client active-address)
curl -X POST http://127.0.0.1:9123/gas \
  -H 'Content-Type: application/json' \
  -d "{\"FixedAmountRequest\":{\"recipient\":\"${SUI_ADDRESS}\"}}"
```

## Publish a Move Package

```bash
sui client publish --gas-budget 100000000 ./path/to/package
```

## Running a PoC

```bash
sui client call \
  --package <PACKAGE_ID> \
  --module <MODULE_NAME> \
  --function <FUNCTION_NAME> \
  --gas-budget 10000000
```

## Reset

```bash
docker compose down -v   # wipes all chain state
docker compose up -d     # fresh chain
```

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Port already in use | `lsof -i :9000` and kill the process |
| Validator not producing blocks | Wait 10–15s after `docker compose up` |
| Faucet returns 500 | Validator may still be initialising — retry |
| Wrong CLI flags | Pin the exact Docker image tag matching your `sui` CLI version |

## Security Note

This setup is for local development only. The validator key is ephemeral and not secured. Never use this configuration on a public network.

## License

[MIT](LICENSE) © kalialucard
