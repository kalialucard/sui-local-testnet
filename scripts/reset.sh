#!/usr/bin/env bash
# Fresh chain. Wallet keys persist (docker volume); chain state and package IDs do not.
set -euo pipefail
docker compose down
rm -f work/local.pub.toml
docker compose up -d
./scripts/wait.sh
docker compose exec -T sui-local sui client switch --env local </dev/null
docker compose exec -T sui-local sui client faucet </dev/null
echo "reset done: republish your packages"
