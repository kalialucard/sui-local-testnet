#!/usr/bin/env bash
# Run any `sui client ...` command against the local chain, from inside ANY
# target folder under ~/hackenproof (or wherever your override mounts).
# Usage (from inside e.g. ~/hackenproof/ScallopProtocol):
#   ~/sui/scripts/sui-here.sh client publish --gas-budget 500000000 .
set -euo pipefail
HOST_ROOT="/home/alucard/hackenproof"   # must match docker-compose.override.yml
CONTAINER_ROOT="/targets"

REL="$(realpath --relative-to="$HOST_ROOT" "$PWD" 2>/dev/null)" || {
  echo "FAIL: current directory is not under $HOST_ROOT"; exit 1; }

docker compose --project-directory /home/alucard/sui exec -T sui-local \
  sh -c "cd ${CONTAINER_ROOT}/${REL} && sui $*"
