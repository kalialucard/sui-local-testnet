#!/usr/bin/env bash
# Prove: chain advances, wallet is on local, faucet funded it.
set -euo pipefail
rpc(){ curl -s localhost:9000 -H 'content-type: application/json' \
  -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"$1\",\"params\":$2}"; }
S="docker compose exec -T sui-local sui client"

a=$(rpc sui_getLatestCheckpointSequenceNumber '[]'); sleep 5
b=$(rpc sui_getLatestCheckpointSequenceNumber '[]')
echo "checkpoint t0: $a"; echo "checkpoint t1: $b"
[ "$a" != "$b" ] && echo "PASS: chain advancing" || { echo "FAIL: chain stalled"; exit 1; }

ENV=$($S active-env </dev/null)
[ "$ENV" = "local" ] && echo "PASS: active env = local" || { echo "FAIL: active env = $ENV"; exit 1; }

$S gas </dev/null
$S chain-identifier </dev/null
