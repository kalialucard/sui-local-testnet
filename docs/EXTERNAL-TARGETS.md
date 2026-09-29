# Testing your own codebase against this local testnet

This rig (`sui-local-testnet`) runs a private Sui chain in Docker. This guide
covers pointing it at Move packages that live in a different folder on your
machine — for example a separate workspace of audit targets — without
touching the main setup.

> Verified 2026-09-30 with `mysten/sui-tools:testnet` (sui 1.81.0-bf0c491c17b8).

## Contents
1. [Layout](#layout)
2. [One-time mount setup](#one-time-mount-setup)
3. [Publishing a target package](#publishing-a-target-package)
4. [Handling build output (read-only mounts)](#handling-build-output-read-only-mounts)
5. [Running attacker/victim PoCs](#running-attackervictim-pocs)
6. [TypeScript PoCs against the running chain](#typescript-pocs-against-the-running-chain)
7. [Multiple unrelated workspaces](#multiple-unrelated-workspaces)
8. [Troubleshooting](#troubleshooting)
9. [Safety](#safety)

## Layout
Example external workspace:
```
~/hackenproof/
├── NAVIProtocol/
├── ScallopProtocol/
├── HaedalSmartContracts/
├── TurbosFinanceSmartContracts/
└── ...
```
Each of these is treated as an independent target. This chain has no relation
to any of these projects' real deployments; publishing here creates a brand
new package at a brand new address on your private genesis.

## One-time mount setup
From the `sui-local-testnet` repo root, add a local override (kept out of git,
since the path is specific to this machine):

```bash
echo "docker-compose.override.yml" >> .gitignore

cat > docker-compose.override.yml <<'YAML'
services:
  sui-local:
    volumes:
      - /home/alucard/hackenproof:/targets:ro
YAML

docker compose up -d       # recreates the container: this resets the chain
./scripts/setup-wallet.sh  # re-fund after reset
```

Recreating the container triggers `--force-regenesis` again, so any packages
published before this point are gone. Do this once, before starting a
session, not mid-PoC.

## Publishing a target package
Use `scripts/publish-target.sh <relative-path-under-the-mounted-folder>`:

```bash
./scripts/publish-target.sh NAVIProtocol
```

This requires a `Move.toml` directly in that folder. If the package lives
deeper (a monorepo with contracts under a subdirectory), give the fuller
path:

```bash
./scripts/publish-target.sh ScallopProtocol/contracts/lending
```

Success prints `Status: Success` and a `PackageID`. Republishing the same
target fails with "already published" — see the main README's `FRESH=1`
note, or the per-package pubfile approach below if you're juggling several
targets in one session.

## Handling build output (read-only mounts)
`test-publish` compiles the package and writes a `build/` directory next to
its `Move.toml`. A read-only mount blocks that write. Two options:

**Per-target writable override** — add a second line to
`docker-compose.override.yml` for the one target you're actively working on:
```yaml
services:
  sui-local:
    volumes:
      - /home/alucard/hackenproof:/targets:ro
      - /home/alucard/hackenproof/NAVIProtocol:/targets/NAVIProtocol
```
`docker compose up -d` to apply (this resets the chain).

**Copy into `work/`** instead of mounting the original at all:
```bash
cp -r /home/alucard/hackenproof/NAVIProtocol ~/sui/work/NAVIProtocol
docker compose exec -T sui-local sui client test-publish \
  --build-env testnet --pubfile-path /work/local.pub.toml \
  --gas-budget 500000000 /work/NAVIProtocol </dev/null
```
This is slower to set up but keeps the original tree untouched and avoids
compose changes per target. Preferred when you don't want `build/` appearing
in the audited repo at all.

Either way, `build/` gets written as root from inside the container. To
clean it up: `sudo rm -rf <package-dir>/build` or
`sudo chown -R $USER <package-dir>` first.

## Running attacker/victim PoCs
Once published, treat the target like any other package on this chain — see
the main README's [Running a PoC](../README.md#running-a-poc) section for the
call/PTB/multi-actor pattern. Summary:
```bash
PKG=<PackageID from publish>
docker compose exec -T sui-local sui client new-address ed25519   # attacker
docker compose exec -T sui-local sui client faucet --address <ATTACKER>
docker compose exec -T sui-local sui client switch --address <ATTACKER>
docker compose exec -T sui-local sui client call \
  --package "$PKG" --module <module> --function <entry_fn> --gas-budget 10000000
```

## TypeScript PoCs against the running chain
Because the compose file uses `network_mode: host`, scripts on your machine
reach the chain directly — no mount needed for this part:
```js
import { SuiClient, getFullnodeUrl } from '@mysten/sui/client';
const client = new SuiClient({ url: 'http://127.0.0.1:9000' }); // or getFullnodeUrl('localnet')
```
Fund a generated keypair via the faucet:
```bash
curl -s -X POST localhost:9123/v2/gas -H 'content-type: application/json' \
  -d '{"FixedAmountRequest":{"recipient":"<ADDR>"}}'
```
Write the PoC anywhere on your machine, including directly inside the target
repo (e.g. `~/hackenproof/NAVIProtocol/poc/`) — the TypeScript side never
needs a container mount, only the published `PackageID`.

## Multiple unrelated workspaces
If you audit targets from more than one parent folder, add one `:ro` line per
folder to the override:
```yaml
services:
  sui-local:
    volumes:
      - /home/alucard/hackenproof:/targets:ro
      - /home/alucard/other-audits:/other-targets:ro
```
Reapply with `docker compose up -d` (resets the chain) and adjust
`publish-target.sh`'s hardcoded host path check if you use it against the
second mount, or call `test-publish` directly with the right `/other-targets/...`
path.

## Troubleshooting
| Symptom | Cause | Fix |
|---|---|---|
| `FAIL: no such dir on host` | `publish-target.sh` checks the *host* path, not the container path | Confirm the folder exists under `~/hackenproof` exactly as named |
| `Failed to publish ... already published` | Ephemeral pubfile already has this package | `FRESH=1 ./scripts/publish.sh` won't touch it — for external targets, use a per-package `--pubfile-path`, e.g. `/work/navi.pub.toml`, or delete `/work/local.pub.toml` if you don't need earlier local packages |
| Publish fails: read-only file system | Package folder is under the `:ro` mount | Use the writable-override or copy-into-`work/` approach above |
| Dependency resolution errors on an older target | Target pins a Sui framework `rev` older/newer than this CLI (1.81.0) | Try `--skip-dependency-verification`, or edit the target's `[dependencies]` rev — note this changes what you're testing |
| `build/` shows up as untracked changes in the target's own git repo | Container writes as root | Add `build/` to that repo's `.gitignore`, or use the copy-into-`work/` approach to avoid touching the original tree |

## Safety
- These are third-party audit targets. Only deploy and test code you're
  authorized to test, per the relevant bug bounty or engagement scope.
- This chain has no mainnet state. A finding here proves the code's logic is
  exploitable; it does not by itself prove impact against any live
  deployment, which may run different bytecode, config or liquidity.
- Do not commit PoCs for undisclosed vulnerabilities to this or any public
  repo before checking the target's disclosure policy.
