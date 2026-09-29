#!/usr/bin/env bash
# Block until both the JSON-RPC (9000) and the faucet (9123) accept connections.
rpc_ok(){ curl -sf localhost:9000 -H 'content-type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"sui_getLatestCheckpointSequenceNumber","params":[]}' >/dev/null; }
faucet_ok(){ curl -s -o /dev/null localhost:9123; }   # any HTTP reply counts; exit 7 = refused

for i in $(seq 1 60); do
  if rpc_ok && faucet_ok; then echo "RPC + faucet up"; exit 0; fi
  sleep 2
done
echo "RPC or faucet never came up"
docker compose logs --tail=50 sui-local | grep -v jwk
exit 1
