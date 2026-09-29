# sui-local-testnet

A private, single-validator Sui network in Docker for local development and
proof-of-concept testing. One command starts the chain, a faucet and the
JSON-RPC endpoint. State is disposable.

| Service  | Address                 |
|----------|-------------------------|
| JSON-RPC | `http://127.0.0.1:9000` |
| Faucet   | `http://127.0.0.1:9123` |

> Verified 2026-09-30 with `mysten/sui-tools:testnet` (sui 1.81.0-bf0c491c17b8). CLI flags change between
> Sui releases; pin an exact image tag if you need reproducibility.

## Contents
1. [Prerequisites](#prerequisites)
2. [Quick start](#quick-start)
3. [Wallet setup](#wallet-setup)
4. [Faucet](#faucet)
5. [Publish and call a package](#publish-and-call-a-package)
6. [Running a PoC](#running-a-poc)
7. [Reset](#reset)
8. [Troubleshooting](#troubleshooting)
9. [Security](#security)
10. [Limitations](#limitations)

## Prerequisites
- Linux with Docker and Docker Compose v2 (`docker compose version`)
- `curl`
- Free ports 9000 and 9123

`network_mode: host` is Linux-only. On macOS/Windows, replace it with published
ports and forward them to `127.0.0.1` inside the container (for example with
`socat`), since the node binds to localhost by default.

## Quick start
```bash
git clone https://github.com/kalialucard/sui-local-testnet.git
cd sui-local-testnet

docker compose up -d        # pulls the image on first run (large)
./scripts/wait.sh           # waits for RPC and faucet
./scripts/setup-wallet.sh   # creates wallet, switches to local, funds it
./scripts/prove.sh          # verifies everything
```

Expected `prove.sh` output:
- two different checkpoint numbers, then `PASS: chain advancing`
- `PASS: active env = local`
- a gas table showing SUI coins with a nonzero balance
- a chain identifier (changes on every fresh genesis)

Convenience alias used below:
```bash
alias suic='docker compose exec sui-local sui client'
```

## Wallet setup
The wallet lives inside the container at `/root/.sui`, persisted in the
`sui-client` Docker volume.

**The client creates its config with `testnet` as the active network.** Until you switch
to `local`, commands go to the public testnet. `scripts/setup-wallet.sh` handles this;
to do it manually:

```bash
suic -y envs                                            # create config without prompting
suic new-env --alias local --rpc http://127.0.0.1:9000  # skip if "already exists"
suic switch --env local
suic active-env                                         # must print: local
suic active-address
```

Extra addresses (for example attacker and victim):
```bash
suic new-address ed25519
suic addresses
suic switch --address <ADDRESS_OR_ALIAS>
```

Never reuse these keys on a public network, and never commit keystore files.

## Faucet
```bash
suic faucet                       # active address
suic faucet --address <ADDRESS>
suic gas                          # list coins and balances
suic balance
```

If the CLI faucet command fails, call the faucet directly. The endpoint path
depends on the Sui version, so try both:
```bash
ADDR=<ADDRESS>
curl -s -X POST localhost:9123/v2/gas -H 'content-type: application/json' \
  -d "{\"FixedAmountRequest\":{\"recipient\":\"$ADDR\"}}"
curl -s -X POST localhost:9123/gas -H 'content-type: application/json' \
  -d "{\"FixedAmountRequest\":{\"recipient\":\"$ADDR\"}}"
```

## Publish and call a package
The example package lives in `work/poc`. The `./work` directory is mounted at `/work`.

```bash
./scripts/publish.sh poc
```
Success shows `Status: Success` and a `PackageID`. Then:

```bash
PKG=<PACKAGE_ID>
suic call --package $PKG --module poc --function mint --gas-budget 10000000
suic objects        # lists <PKG>::poc::Marker
```

Republishing a package fails with "already published", because the ephemeral
pubfile records it. Discard the pubfile and publish again:
```bash
FRESH=1 ./scripts/publish.sh poc
```
This forgets every local publication. Republish dependencies first, in order.

Notes on the publish command:
- The CLI's `test-publish` publishes to the current network (local) but needs
  a build environment and an ephemeral publication file. That is why
  `--build-env testnet --pubfile-path /work/local.pub.toml` is passed. The
  Sui framework has the same addresses (`0x1`, `0x2`) on every network, so
  dependencies resolve.
- `local.pub.toml` records addresses from this chain. It is git-ignored and is
  deleted on reset.
- Publish merges your gas coins into one. Use `suic split-coin` if a PoC needs
  separate coins.

## Running a PoC
1. Put the target Move package in `work/<name>/`.
2. `./scripts/publish.sh <name>`
3. Create and fund actor addresses (see [Wallet setup](#wallet-setup)).
4. Execute the exploit as a single call, an atomic PTB, or an SDK script
   against `http://127.0.0.1:9000`:
```bash
   suic ptb --help
   suic ptb --move-call $PKG::poc::mint --gas-budget 10000000
```
5. Inspect results: `suic tx-block <DIGEST>` and `suic objects`.

Always run `suic active-env` first. It must print `local`.

## Reset
```bash
./scripts/reset.sh
```
Restarts with a fresh genesis, deletes `work/local.pub.toml` and funds the
active address. Package IDs and objects from the previous chain are gone.

`docker compose down -v` also deletes the wallet volume. Only use it to wipe the wallet.

## Troubleshooting
| Symptom | Cause | Fix |
|---|---|---|
| Script hangs on `sui client ...` | First-run config prompt, no TTY | Use `sui client -y envs` (done in `setup-wallet.sh`) |
| Commands hit public testnet | Fresh config defaults to `testnet` | `suic switch --env local`, check `suic active-env` |
| `Ephemeral publication file does not exist ... --build-env` | `test-publish` needs an env | Use `scripts/publish.sh` |
| `Environment config with name [local] already exists` | Env already registered | Harmless; run `suic switch --env local` |
| Logs flooded with `Submitting JWK to consensus` | zkLogin JWK updater | Ignore; `docker compose logs sui-local \| grep -v jwk` |
| `rm` or `git clean` fails with "Permission denied" under `work/` | The container runs as root and wrote `work/*/build/` | `sudo chown -R $USER work`, or `sudo rm -rf` the directory |
| Startup fails when `/tmp` is tmpfs | Node data dir in `/tmp` | Set `TMPDIR` to a real directory in the compose file |
| Faucet 404 | Endpoint differs by version | Try `/v2/gas` and `/gas` |
| Faucet `Connection refused` on port 9123 | Faucet starts a moment after RPC | Run `./scripts/wait.sh`, then retry |
| Old package ID not found | Chain was reset | Republish |

## Security
- For authorized testing only. Do not use this against systems you have no
  permission to test.
- Do not commit PoCs for undisclosed vulnerabilities in live protocols to a
  public repo. Check the target's bug bounty disclosure rules first.
- The faucet is unauthenticated and the ports are open on the host. Do not
  expose 9000 or 9123 to untrusted networks.
- Wallet keys here are throwaway. Never import real keys.

## Limitations
- Fresh genesis: no mainnet or testnet state, no real liquidity or oracle
  values. Deploy the target's code and seed your own state. Results are a
  local reproduction, not a mainnet fork.
- Single validator: consensus and multi-validator behavior are not exercised.
- Epochs advance quickly on this network (it went from epoch 6 to 7 within
  minutes). Account for that in epoch-dependent PoCs.

## License
MIT
