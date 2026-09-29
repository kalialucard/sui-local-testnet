#!/usr/bin/env bash
# Usage: scripts/publish.sh <package-dir-under-work>   (default: poc)
# FRESH=1 scripts/publish.sh poc   -> discard the ephemeral pubfile first (republish)
set -euo pipefail
PKG_DIR="${1:-poc}"
S="docker compose exec -T sui-local sui client"
[ "$($S active-env </dev/null)" = "local" ] || { echo "FAIL: active env is not local"; exit 1; }
[ "${FRESH:-0}" = "1" ] && rm -f work/local.pub.toml
$S test-publish \
  --build-env testnet \
  --pubfile-path /work/local.pub.toml \
  --gas-budget 500000000 \
  "/work/${PKG_DIR}" </dev/null \
  || { echo "If this says 'already published': rerun with FRESH=1 (drops all recorded local publications)."; exit 1; }
