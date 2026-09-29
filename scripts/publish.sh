#!/usr/bin/env bash
# Usage: scripts/publish.sh <package-dir-under-work>   (default: poc)
set -euo pipefail
PKG_DIR="${1:-poc}"
S="docker compose exec -T sui-local sui client"
[ "$($S active-env </dev/null)" = "local" ] || { echo "FAIL: active env is not local"; exit 1; }
$S test-publish \
  --build-env testnet \
  --pubfile-path /work/local.pub.toml \
  --gas-budget 500000000 \
  "/work/${PKG_DIR}" </dev/null
