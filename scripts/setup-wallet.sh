#!/usr/bin/env bash
# Create the client config + wallet, register the local env, switch to it, fund the address.
set -euo pipefail
./scripts/wait.sh
S="docker compose exec -T sui-local sui client"

$S -y envs </dev/null >/dev/null                     # -y: create config non-interactively
$S new-env --alias local --rpc http://127.0.0.1:9000 </dev/null >/dev/null 2>&1 || true
$S switch --env local </dev/null

ENV=$($S active-env </dev/null)
[ "$ENV" = "local" ] || { echo "FAIL: active env is '$ENV', expected 'local'"; exit 1; }

echo "active env    : $ENV"
echo "active address: $($S active-address </dev/null)"

$S faucet </dev/null
sleep 3
$S gas </dev/null
