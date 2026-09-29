# Running your own PoC against this private testnet

This guide is for anyone who already has this repo's Sui chain running and
wants to test a Move package or PoC that lives in a **separate folder or
workspace on their machine** — a security audit target, a client's codebase,
a different git repo, anything outside this project.

You never need to copy files into this repo or edit any script's contents.
Everything below uses a local override file plus one environment variable.

## Contents
1. [How it works](#how-it-works)
2. [Step 1: point the container at your workspace](#step-1-point-the-container-at-your-workspace)
3. [Step 2: publish a package from your workspace](#step-2-publish-a-package-from-your-workspace)
4. [Step 3: run your PoC](#step-3-run-your-poc)
5. [Working with several workspaces](#working-with-several-workspaces)
6. [Build output and read-only mounts](#build-output-and-read-only-mounts)
7. [Troubleshooting](#troubleshooting)
8. [Safety](#safety)

## How it works
Docker containers only see folders you explicitly mount. This repo's
`docker-compose.yml` mounts `./work` by default. To reach a folder anywhere
else — `~/my-audits`, `~/client-project`, a cloned repo, whatever — you add
your own `docker-compose.override.yml`, which Docker Compose merges
automatically on top of the base file. It is never committed (see
`.gitignore`), so each person on this rig points it at their own paths
without touching shared files.

## Step 1: point the container at your workspace
In the repo root, create the override once (edit the left-hand host path to
match your machine):

```bash
cat > docker-compose.override.yml <<'YAML'
services:
  sui-local:
    volumes:
      - /absolute/path/to/your/workspace:/targets:ro
YAML

docker compose up -d       # applies the mount — this restarts the chain
./scripts/setup-wallet.sh  # re-fund after the restart
```

Replace `/absolute/path/to/your/workspace` with wherever your code actually
lives, for example `/home/alucard/my-audits` or `/home/alucard/client-repo`.
Mount the **parent folder** if you'll work across several projects inside it
(see [Working with several workspaces](#working-with-several-workspaces)),
or a **single project folder** if you only need one.

`:ro` (read-only) means the container can read your code but never modify
it. Some build tooling needs to write output next to the source — see
[Build output and read-only mounts](#build-output-and-read-only-mounts) for
how to handle that without giving up the read-only guarantee everywhere
else.

Recreating the container restarts the chain (`--force-regenesis`), so do
this once at the start of a session, not mid-PoC.

## Step 2: publish a package from your workspace
`scripts/publish-target.sh` takes two inputs: the `TARGET_DIR` environment
variable (the same host path you put in the override) and the path to the
package inside it (wherever `Move.toml` sits):

```bash
TARGET_DIR=/absolute/path/to/your/workspace \
  ./scripts/publish-target.sh <path-to-package-with-Move.toml>
```

Example: your workspace is `~/my-audits`, and the package you want to test
is at `~/my-audits/SomeProtocol/contracts`:
```bash
TARGET_DIR=/home/alucard/my-audits \
  ./scripts/publish-target.sh SomeProtocol/contracts
```

If you don't know where `Move.toml` is inside a project, find it first:
```bash
find /absolute/path/to/your/workspace -iname Move.toml
```

Success prints `Status: Success` and a `PackageID`. Save it — you'll pass it
to your PoC.

Publishing the same package again fails with "already published" (the
ephemeral pubfile remembers it). Either:
- use a separate pubfile per target: `PUBFILE=someprotocol.pub.toml TARGET_DIR=... ./scripts/publish-target.sh ...`
- or clear the shared one: `rm work/local.pub.toml` and republish.

## Step 3: run your PoC
Once published, everything from the main README's
[Running a PoC](../README.md#running-a-poc) section applies as normal:
create attacker/victim addresses, fund them, call the package, inspect
effects with `sui client tx-block` and `sui client objects`.

For scripted (TypeScript/JS) PoCs you don't need the mount at all — this
compose file uses `network_mode: host`, so any script on your machine reaches
the chain directly:
```js
import { SuiClient } from '@mysten/sui/client';
const client = new SuiClient({ url: 'http://127.0.0.1:9000' });
```
Faucet: `POST http://127.0.0.1:9123/v2/gas` with
`{"FixedAmountRequest":{"recipient":"<address>"}}`.

Write and run the PoC script wherever you like — inside your own workspace,
alongside the target code, or anywhere else on your machine. Only the
published `PackageID` and the chain's local RPC address matter.

## Working with several workspaces
Add one line per folder to the override:
```yaml
services:
  sui-local:
    volumes:
      - /home/alucard/my-audits:/targets:ro
      - /home/alucard/client-repo:/targets2:ro
```
Then publish from either, using the container path that matches the mount
(`/targets/...` or `/targets2/...`). `publish-target.sh` assumes container
path `/targets/<subpath>`; for a second mount, either add a second script
with the same pattern pointed at `/targets2`, or call `test-publish`
directly:
```bash
docker compose exec -T sui-local sui client test-publish \
  --build-env testnet --pubfile-path /work/client.pub.toml \
  --gas-budget 500000000 /targets2/<path> </dev/null
```
Reapply the override with `docker compose up -d` (resets the chain) whenever
you add or change a mount.

## Build output and read-only mounts
Building a Move package writes a `build/` folder next to `Move.toml`. A
`:ro` mount blocks that write, so publishing will fail with a filesystem
error unless you do one of the following:

**Option A — writable override for one package**, keeping everything else
read-only:
```yaml
services:
  sui-local:
    volumes:
      - /home/alucard/my-audits:/targets:ro
      - /home/alucard/my-audits/SomeProtocol:/targets/SomeProtocol
```

**Option B — copy the package into this repo's `work/` folder** before
publishing, leaving the original completely untouched:
```bash
cp -r /home/alucard/my-audits/SomeProtocol ~/sui/work/SomeProtocol
docker compose exec -T sui-local sui client test-publish \
  --build-env testnet --pubfile-path /work/local.pub.toml \
  --gas-budget 500000000 /work/SomeProtocol </dev/null
```
Option B is the simpler default if you're unsure — no compose edits, no risk
of ever writing into someone else's repo.

Either way, `build/` is written as root from inside the container. Clean up
with `sudo rm -rf <package>/build` or `sudo chown -R $USER <package>` first.

## Troubleshooting
| Symptom | Cause | Fix |
|---|---|---|
| `TARGET_DIR: unbound variable` | forgot to set the env var | prefix the command: `TARGET_DIR=/your/path ./scripts/publish-target.sh ...` |
| `FAIL: not found on host` | path typo, or override not applied yet | `docker compose exec -T sui-local ls /targets` to confirm the mount is live |
| Publish fails: read-only file system | package sits under a `:ro`-only mount | use Option A or B above |
| `already published` | ephemeral pubfile already has this package | use `PUBFILE=<name>.pub.toml`, or delete `work/local.pub.toml` |
| Dependency/framework version errors | target pins a different Sui framework revision than this CLI supports | try `--skip-dependency-verification`, or edit that target's `[dependencies]` rev (changes what you're testing) |
| `docker compose up -d` didn't seem to remount | compose caches the old container | `docker compose down && docker compose up -d` |

## Safety
- Only test code you're authorized to test, under the relevant engagement or
  bug bounty scope.
- This chain has no mainnet state, no real liquidity, no real oracle values.
  A finding here proves the code's logic is exploitable in isolation, not
  that the same exploit works against any live deployment.
- Never commit PoCs for undisclosed vulnerabilities in third-party code to a
  public repo before checking that project's disclosure policy.
- `docker-compose.override.yml` is git-ignored on purpose — it contains
  machine-specific paths and should never be pushed.
