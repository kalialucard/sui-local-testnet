#!/usr/bin/env bash
# Block until the local RPC answers.
for i in $(seq 1 60); do
  curl -sf localhost:9000 -H 'content-type: application/json' \
    -d '{"jsonrpc":"2.0","id":1,"method":"sui_getLatestCheckpointSequenceNumber","params":[]}' >/dev/null \
    && { echo "RPC up"; exit 0; }
  sleep 2
done
echo "RPC never came up"
docker compose logs --tail=50 sui-local | grep -v jwk
exit 1
