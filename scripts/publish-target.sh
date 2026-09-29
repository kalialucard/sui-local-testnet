#!/usr/bin/env bash
# Usage: scripts/publish-target.sh <path-under-/targets-to-the-Move-package-dir>
# Example: scripts/publish-target.sh NAVIProtocol/contracts/lending
set -euo pipefail
TARGET="${1:?usage: scripts/publish-target.sh <relative-path-under-hackenproof>}"
S="docker compose exec -T sui-local sui client"

[ "$($S active-env </dev/null)" = "local" ] || { echo "FAIL: active env is not local"; exit 1; }
[ -d "/home/alucard/hackenproof/${TARGET}" ] || { echo "FAIL: no such dir on host: hackenproof/${TARGET}"; exit 1; }
[ -f "/home/alucard/hackenproof/${TARGET}/Move.toml" ] || { echo "FAIL: no Move.toml at hackenproof/${TARGET}"; exit 1; }

$S test-publish \
  --build-env testnet \
  --pubfile-path /work/local.pub.toml \
  --gas-budget 500000000 \
  "/targets/${TARGET}" </dev/null \
  || { echo "If this says 'already published': rerun with FRESH=1 (or use a package-specific pubfile, see docs/EXTERNAL-TARGETS.md)."; exit 1; }
