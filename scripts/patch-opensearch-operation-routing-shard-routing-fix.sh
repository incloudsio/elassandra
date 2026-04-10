#!/usr/bin/env bash
# OpenSearch 1.3 RoutingTable.shardRoutingTable(String,int) — fix mistaken static call in OperationRouting#computeTargetedShards.
#
# Usage: ./scripts/patch-opensearch-operation-routing-shard-routing-fix.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
OR="$DEST/server/src/main/java/org/opensearch/cluster/routing/OperationRouting.java"
[[ -f "$OR" ]] || exit 0

python3 - "$OR" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
old = "set.add(RoutingTable.shardRoutingTable(indexRouting, calculateScaledShardId(indexMetadata, r, partitionOffset)));"
new = "set.add(clusterState.routingTable().shardRoutingTable(index, calculateScaledShardId(indexMetadata, r, partitionOffset)));"
if old not in text:
    if new in text:
        print("OperationRouting computeTargetedShards already fixed:", path)
        raise SystemExit(0)
    print("patch: expected OperationRouting line not found", file=sys.stderr)
    sys.exit(1)
path.write_text(text.replace(old, new, 1), encoding="utf-8")
print("Patched OperationRouting shardRoutingTable call →", path)
PY
