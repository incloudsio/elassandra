#!/usr/bin/env bash
# OpenSearch 1.3: Elassandra routing overlay uses ES 6.8 DiffableUtils 4-arg readImmutableOpenMapDiff;
# stock OS only has 3-arg + DiffableValueReader. Also expand UnassignedInfo statics to 9-arg ctor.
#
# Run after sync-elassandra-routing-overlay + rewrite-elassandra-imports-for-opensearch.
#
# Usage: ./scripts/patch-opensearch-routing-table-for-os13.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
RT="$DEST/server/src/main/java/org/opensearch/cluster/routing/RoutingTable.java"
IRT="$DEST/server/src/main/java/org/opensearch/cluster/routing/IndexRoutingTable.java"
[[ -f "$RT" ]] || exit 0

python3 - "$RT" <<'PY'
from pathlib import Path
import re
import sys
path = Path(sys.argv[1])
t = path.read_text(encoding="utf-8")
old = """            indicesRouting = DiffableUtils.readImmutableOpenMapDiff(in, DiffableUtils.getStringKeySerializer(), IndexRoutingTable::readFrom,
                IndexRoutingTable::readDiffFrom);"""
new = """            indicesRouting = DiffableUtils.readImmutableOpenMapDiff(
                in,
                DiffableUtils.getStringKeySerializer(),
                new DiffableUtils.DiffableValueReader<>(IndexRoutingTable::readFrom, IndexRoutingTable::readDiffFrom)
            );"""
if old in t:
    t = t.replace(old, new, 1)
    path.write_text(t, encoding="utf-8")
    print("Patched RoutingTableDiff readImmutableOpenMapDiff →", path)
elif "DiffableValueReader<>(IndexRoutingTable::readFrom" in t:
    print("RoutingTableDiff already OS 1.3 style:", path)
else:
    print("patch-opensearch-routing-table-for-os13: expected RoutingTableDiff block not found", file=sys.stderr)
    sys.exit(1)
PY

[[ -f "$IRT" ]] || exit 0
python3 - "$IRT" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
t = path.read_text(encoding="utf-8")
repls = [
    (
        "new UnassignedInfo(UnassignedInfo.Reason.ALLOCATION_FAILED, \"cassandra node left\", null, 1, 0, 0, false, AllocationStatus.DECIDERS_NO)",
        """new UnassignedInfo(
        UnassignedInfo.Reason.ALLOCATION_FAILED,
        "cassandra node left",
        null,
        1,
        System.nanoTime(),
        System.currentTimeMillis(),
        false,
        AllocationStatus.DECIDERS_NO,
        java.util.Collections.emptySet()
    )""",
    ),
    (
        "new UnassignedInfo(UnassignedInfo.Reason.ALLOCATION_FAILED, \"shard or keyspace unavailable\", null, 1, 0, 0, false, AllocationStatus.DECIDERS_NO)",
        """new UnassignedInfo(
        UnassignedInfo.Reason.ALLOCATION_FAILED,
        "shard or keyspace unavailable",
        null,
        1,
        System.nanoTime(),
        System.currentTimeMillis(),
        false,
        AllocationStatus.DECIDERS_NO,
        java.util.Collections.emptySet()
    )""",
    ),
]
changed = False
for old, new in repls:
    if old in t:
        t = t.replace(old, new, 1)
        changed = True
if changed:
    path.write_text(t, encoding="utf-8")
    print("Patched UnassignedInfo statics →", path)
else:
    if "Collections.emptySet()" in t and "UNASSIGNED_INFO_NODE_LEFT" in t:
        print("UnassignedInfo statics already OS 1.3 style:", path)
    else:
        print("patch-opensearch-routing-table-for-os13: UnassignedInfo 8-arg pattern not found", file=sys.stderr)
        sys.exit(1)
PY
