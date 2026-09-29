#!/usr/bin/env bash
# Publish a Move package from ANY folder on your machine, not just ./work.
#
# Usage:
#   TARGET_DIR=/absolute/path/to/your/workspace scripts/publish-target.sh <pkg-subpath>
#
# TARGET_DIR must match the host path given to docker-compose.override.yml
# (see docs/EXTERNAL-TARGETS.md). <pkg-subpath> is the path to the Move
# package *inside* TARGET_DIR, i.e. the folder containing Move.toml.
#
# Example:
#   TARGET_DIR=/home/alucard/my-audits scripts/publish-target.sh SomeProtocol/contracts
#
# Optional: PUBFILE=name.pub.toml to keep this target's publications separate
# from ./work's own packages (avoids "already published" collisions).
set -euo pipefail
: "${TARGET_DIR:?set TARGET_DIR to the absolute host path you mounted in docker-compose.override.yml}"
PKG_SUBPATH="${1:?usage: TARGET_DIR=/host/path scripts/publish-target.sh <pkg-subpath-with-Move.toml>}"
PUBFILE="${PUBFILE:-local.pub.toml}"

S="docker compose exec -T sui-local sui client"

[ "$($S active-env </dev/null)" = "local" ] || { echo "FAIL: active env is not local"; exit 1; }
[ -d "${TARGET_DIR}/${PKG_SUBPATH}" ] || { echo "FAIL: not found on host: ${TARGET_DIR}/${PKG_SUBPATH}"; exit 1; }
[ -f "${TARGET_DIR}/${PKG_SUBPATH}/Move.toml" ] || { echo "FAIL: no Move.toml at ${TARGET_DIR}/${PKG_SUBPATH}"; exit 1; }

echo "Publishing container path: /targets/${PKG_SUBPATH}"
echo "Pubfile: /work/${PUBFILE}"

$S test-publish \
  --build-env testnet \
  --pubfile-path "/work/${PUBFILE}" \
  --gas-budget 500000000 \
  "/targets/${PKG_SUBPATH}" </dev/null \
  || { echo "If this says 'already published': use a different PUBFILE=<name>.pub.toml, or delete /work/${PUBFILE} inside the container's mounted ./work folder on the host."; exit 1; }
