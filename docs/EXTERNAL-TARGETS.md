# Testing your own code against this private testnet

This chain runs in Docker. Your code doesn't have to. This guide explains
the two ways to connect a Move package — in any folder, anywhere on your
machine — to the chain, and why one of them is almost always what you want.

> Verified 2026-09-30. Host CLI approach tested against a real ~30-module
> DeFi protocol (Momentum CLMM) and a HackenProof bug-bounty package
> (Haedal), both published successfully with zero container involvement.

## Contents
1. [The short answer](#the-short-answer)
2. [Why this works: what Docker is actually doing here](#why-this-works-what-docker-is-actually-doing-here)
3. [Method A — host CLI (recommended)](#method-a--host-cli-recommended)
4. [Method B — CLI inside the container (fallback)](#method-b--cli-inside-the-container-fallback)
5. [Common publish issues on real-world repos](#common-publish-issues-on-real-world-repos)
6. [Which method should I actually use?](#which-method-should-i-actually-use)
7. [Safety](#safety)

## The short answer

Install the `sui` CLI on your host machine once. Then treat this chain like
any local Sui node you'd run for development — `cd` into whatever folder has
your target's `Move.toml` and run `sui client publish` directly. No mounts,
no `docker compose exec`, no wrapper scripts, no `TARGET_DIR` variables.

```bash
# one-time
sui client new-env --alias local --rpc http://127.0.0.1:9000
sui client switch --env local
sui client faucet

# every target, forever after
cd ~/wherever/your/target/lives
sui client test-publish --build-env testnet --pubfile-path ./local.pub.toml --gas-budget 500000000 .
```

That's it. `~/sui` (this repo) becomes purely "where the chain lives" —
`docker compose up -d` to start it, nothing else. Every PoC runs in its own
folder using the host CLI, same as normal local Move development.

## Why this works: what Docker is actually doing here

`docker-compose.yml` uses `network_mode: host`, so the chain's RPC
(`127.0.0.1:9000`) and faucet (`127.0.0.1:9123`) are reachable from anywhere
on the host — no container access needed to talk to the chain. The `sui`
binary only needs to exist *somewhere* that can reach those ports; it
doesn't need to run inside the same container as the node.

Earlier versions of this doc routed everything through
`docker compose exec sui-local sui client ...`, which meant every target
folder had to be bind-mounted into the container (`docker-compose.override.yml`),
every command needed a full container-path translation, and case-sensitive
filenames (`move.toml` vs `Move.toml`) or embedded `.git` folders caused
friction that had nothing to do with the actual chain. None of that
complexity was necessary — it was a side effect of assuming the CLI had to
run in the same place as the node. It doesn't.

## Method A — host CLI (recommended)

**Install**, matching the chain's Sui version where possible:
```bash
docker compose exec -T sui-local sui --version   # check what the chain expects
```
Then install a matching (or close) release from
[the Sui releases page](https://github.com/MystenLabs/sui/releases), or via
cargo:
```bash
cargo install --locked --git https://github.com/MystenLabs/sui.git --tag testnet-v<VERSION> sui
```

**Connect it to the running chain** (one-time, persists in `~/.sui` on your
host — separate from the container's own `~/.sui` volume):
```bash
sui client new-env --alias local --rpc http://127.0.0.1:9000
sui client switch --env local
sui client faucet
sui client gas   # confirm funded
```

**Work normally, in any folder:**
```bash
cd ~/hackenproof/SomeProtocol/some-package
sui client active-env                 # confirm: local
sui client test-publish \
  --build-env testnet \
  --pubfile-path ./local.pub.toml \
  --gas-budget 500000000 \
  .
```

`local.pub.toml` lands next to that package's own `Move.toml` — self
contained, one per target, no collisions. It's not your repo's file, so
don't commit it into someone else's checked-out codebase; if that folder is
its own git repo, add `local.pub.toml` to your global gitignore
(`~/.gitignore_global`) rather than editing their `.gitignore`.

Then call functions, run PTBs, inspect state — all exactly as documented in
the main [README's Running a PoC section](../README.md#running-a-poc), just
without the `docker compose exec` prefix:
```bash
sui client call --package <PKG> --module <mod> --function <fn> --gas-budget 10000000
sui client objects
sui client tx-block <DIGEST>
```

**Chain lifecycle stays in Docker**, unrelated to any of the above:
```bash
cd ~/sui
docker compose up -d       # start (or restart after reboot — resets the chain, refund after)
docker compose down        # stop
```

## Method B — CLI inside the container (fallback)

Use this only if you can't or don't want to install `sui` on the host (e.g.
locked-down machine, avoiding version conflicts with something else). It
mounts your target folder into the container so the container's own `sui`
binary can see it.

```bash
cat > docker-compose.override.yml <<'YAML'
services:
  sui-local:
    volumes:
      - /absolute/path/to/your/workspace:/targets:ro
YAML
docker compose up -d && ./scripts/setup-wallet.sh
```

Then, from *inside* the repo root (not the target folder — the container
doesn't know your host paths):
```bash
docker compose exec -T sui-local sui client test-publish \
  --build-env testnet --pubfile-path /work/some-target.pub.toml \
  --gas-budget 500000000 /targets/<path-to-package>
```

Known friction with this method, encountered in practice:
- The mount is `:ro`, so the build step's `build/` output directory can't be
  written unless you either add a writable override for that one package or
  copy the package into `./work/` first (see git history of this file for
  the copy-based recipe if needed).
- Filenames must match exactly what the CLI expects (`Move.toml`, not
  `move.toml`) — you can't rename a file on a read-only mount, so this
  forces the copy-into-`work/` path for any repo with the lowercase variant.
- Copying a git-tracked target repo into `./work/` risks it being picked up
  as a nested git repository if not careful; `work/*/` is gitignored in this
  repo specifically to prevent that (see `.gitignore`).
- Every command needs the container-path translation from your host path,
  which is where most of the friction in this file used to live.

None of these are blockers, just added steps that Method A skips entirely.

## Common publish issues on real-world repos

These apply to both methods, since they come from the target codebase, not
from Docker or the CLI location:

| Symptom | Cause | Fix |
|---|---|---|
| `Package does not have a Move.toml file` | wrong directory, or file is `move.toml` (lowercase) | `find <dir> -iname Move.toml`; rename with `mv move.toml Move.toml` if you're on the host filesystem |
| `the package does not define an 'local' environment` | package's `Move.toml` has explicit `[environments]` but no `local` entry | use `sui client test-publish --pubfile-path ./local.pub.toml ...` instead of plain `publish` |
| `Ephemeral publication file ... has chain-id X; it cannot be used to publish to chain with id Y` | chain was reset (new genesis) since that pubfile was created | delete the stale `local.pub.toml` and republish |
| `already published` | this exact pubfile already recorded this package | delete `local.pub.toml` in that folder, or use `--pubfile-path` pointing at a new file |
| `CLI's protocol version is X, but the active network's protocol version is Y` | host/container CLI version doesn't exactly match the chain's genesis version | cosmetic in most cases; if publish then fails with a dependency verification error, install a matching CLI version |
| dependency resolution / framework `rev` errors | target pins an older or newer Sui framework revision than your CLI supports | try `--skip-dependency-verification`, or note that this changes what's actually being tested |
| `warning: refname '<hash>' is ambiguous` during `git checkout` | Move's dependency resolver pinning a framework commit; harmless | ignore |

## Which method should I actually use?

**Method A (host CLI)** unless you have a specific reason not to install
`sui` locally. It's simpler, faster, and every quirk above becomes a normal
one-line fix instead of a container-path puzzle.

**Method B (container)** only if the host CLI genuinely can't be installed,
or you specifically want the chain and your tooling fully isolated from the
host (e.g. CI, a shared machine, or deliberately avoiding any local Sui
install).

## Safety
- Only test code you're authorized to test, per the relevant engagement or
  bug bounty scope.
- This chain has no mainnet state, no real liquidity, no real oracle values.
  A successful publish and a working exploit here proves the code's logic is
  exploitable in isolation — it does not by itself prove impact against any
  live deployment, which may run different bytecode, config, or liquidity.
- Never commit PoCs for undisclosed vulnerabilities in third-party code to a
  public repo before checking that project's disclosure policy.
