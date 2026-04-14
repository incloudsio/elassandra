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

python3 - "$RT" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
t = path.read_text(encoding="utf-8")

full_old = """        for(ObjectObjectCursor<String, IndexMetadata> entry : clusterState.metadata().getIndices()) {\n            IndexRoutingTable.Builder indexRoutingTableBuilder = new IndexRoutingTable.Builder(entry.value.getIndex(), clusterService, clusterState);\n            if (indexRoutingTableBuilder.shards.size() > 0)\n                indicesRoutingMap.put(indexRoutingTableBuilder.index.getName(), indexRoutingTableBuilder.build());\n        }\n"""
full_old_fallback = """        for(ObjectObjectCursor<String, IndexMetadata> entry : clusterState.metadata().getIndices()) {\n            IndexRoutingTable.Builder indexRoutingTableBuilder = new IndexRoutingTable.Builder(entry.value.getIndex(), clusterService, clusterState);\n            if (indexRoutingTableBuilder.shards.size() > 0) {\n                indicesRoutingMap.put(indexRoutingTableBuilder.index.getName(), indexRoutingTableBuilder.build());\n            } else {\n                IndexRoutingTable existing = clusterState.routingTable().index(entry.value.getIndex());\n                if (existing != null) {\n                    indicesRoutingMap.put(existing.getIndex().getName(), existing);\n                }\n            }\n        }\n"""
full_new = """        for(ObjectObjectCursor<String, IndexMetadata> entry : clusterState.metadata().getIndices()) {\n            IndexRoutingTable existing = clusterState.routingTable().index(entry.value.getIndex());\n            try {\n                IndexRoutingTable.Builder indexRoutingTableBuilder = new IndexRoutingTable.Builder(entry.value.getIndex(), clusterService, clusterState);\n                if (indexRoutingTableBuilder.shards.size() > 0) {\n                    indicesRoutingMap.put(indexRoutingTableBuilder.index.getName(), indexRoutingTableBuilder.build());\n                } else if (existing != null) {\n                    indicesRoutingMap.put(existing.getIndex().getName(), existing);\n                }\n            } catch (RuntimeException e) {\n                if (existing == null) {\n                    throw e;\n                }\n                indicesRoutingMap.put(existing.getIndex().getName(), existing);\n            }\n        }\n"""

many_old = """        for(Index index : indices) {\n            IndexRoutingTable.Builder indexRoutingTableBuilder = new IndexRoutingTable.Builder(index, clusterService, clusterState);\n            if (indexRoutingTableBuilder.shards.size() > 0)\n                indicesRoutingMap.put(indexRoutingTableBuilder.index.getName(), indexRoutingTableBuilder.build());\n        }\n"""
many_old_fallback = """        for(Index index : indices) {\n            IndexRoutingTable.Builder indexRoutingTableBuilder = new IndexRoutingTable.Builder(index, clusterService, clusterState);\n            if (indexRoutingTableBuilder.shards.size() > 0) {\n                indicesRoutingMap.put(indexRoutingTableBuilder.index.getName(), indexRoutingTableBuilder.build());\n            } else {\n                IndexRoutingTable existing = clusterState.routingTable().index(index);\n                if (existing != null) {\n                    indicesRoutingMap.put(existing.getIndex().getName(), existing);\n                }\n            }\n        }\n"""
many_new = """        for(Index index : indices) {\n            IndexRoutingTable existing = clusterState.routingTable().index(index);\n            try {\n                IndexRoutingTable.Builder indexRoutingTableBuilder = new IndexRoutingTable.Builder(index, clusterService, clusterState);\n                if (indexRoutingTableBuilder.shards.size() > 0) {\n                    indicesRoutingMap.put(indexRoutingTableBuilder.index.getName(), indexRoutingTableBuilder.build());\n                } else if (existing != null) {\n                    indicesRoutingMap.put(existing.getIndex().getName(), existing);\n                }\n            } catch (RuntimeException e) {\n                if (existing == null) {\n                    throw e;\n                }\n                indicesRoutingMap.put(existing.getIndex().getName(), existing);\n            }\n        }\n"""

one_old = """        if (indexMetaData != null) {\n            IndexRoutingTable.Builder indexRoutingTableBuilder = new IndexRoutingTable.Builder(index, clusterService, clusterState);\n            if (indexRoutingTableBuilder.shards.size() > 0)\n                indicesRoutingMap.put(index.getName(), indexRoutingTableBuilder.build());\n        }\n"""
one_old_fallback = """        if (indexMetaData != null) {\n            IndexRoutingTable.Builder indexRoutingTableBuilder = new IndexRoutingTable.Builder(index, clusterService, clusterState);\n            if (indexRoutingTableBuilder.shards.size() > 0) {\n                indicesRoutingMap.put(index.getName(), indexRoutingTableBuilder.build());\n            } else {\n                IndexRoutingTable existing = clusterState.routingTable().index(index);\n                if (existing != null) {\n                    indicesRoutingMap.put(existing.getIndex().getName(), existing);\n                }\n            }\n        }\n"""
one_new = """        if (indexMetaData != null) {\n            IndexRoutingTable existing = clusterState.routingTable().index(index);\n            try {\n                IndexRoutingTable.Builder indexRoutingTableBuilder = new IndexRoutingTable.Builder(index, clusterService, clusterState);\n                if (indexRoutingTableBuilder.shards.size() > 0) {\n                    indicesRoutingMap.put(index.getName(), indexRoutingTableBuilder.build());\n                } else if (existing != null) {\n                    indicesRoutingMap.put(existing.getIndex().getName(), existing);\n                }\n            } catch (RuntimeException e) {\n                if (existing == null) {\n                    throw e;\n                }\n                indicesRoutingMap.put(existing.getIndex().getName(), existing);\n            }\n        }\n"""

changed = False
for old, new in (
    (full_old, full_new),
    (full_old_fallback, full_new),
    (many_old, many_new),
    (many_old_fallback, many_new),
    (one_old, one_new),
    (one_old_fallback, one_new),
):
    if old in t:
        t = t.replace(old, new, 1)
        changed = True

if changed:
    path.write_text(t, encoding="utf-8")
    print("Patched RoutingTable build() to preserve existing routes →", path)
elif "catch (RuntimeException e)" in t and "IndexRoutingTable existing = clusterState.routingTable().index(entry.value.getIndex());" in t:
    print("RoutingTable build() route preservation already present:", path)
else:
    print("patch-opensearch-routing-table-for-os13: route preservation anchors not found", file=sys.stderr)
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

# Restore AllocationService-critical implementation: Elassandra had commented out RoutingTable.Builder.updateNodes,
# which made every reroute produce an empty routing table (IndexNotFoundException in IndexMetadataUpdater).
RT2="$DEST/server/src/main/java/org/opensearch/cluster/routing/RoutingTable.java"
[[ -f "$RT2" ]] || exit 0
python3 - "$RT2" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
t = path.read_text(encoding="utf-8")
if "private static void addShard(" in t and "addShard(indexRoutingTableBuilders, shardRoutingEntry)" in t:
    print("RoutingTable.Builder.updateNodes already restored:", path)
    sys.exit(0)

old = """        public Builder updateNodes(long version, RoutingNodes routingNodes) {
            // this is being called without pre initializing the routing table, so we must copy over the version as well
            /*
            this.version = version;


            Map<String, IndexRoutingTable.Builder> indexRoutingTableBuilders = new HashMap<>();
            for (RoutingNode routingNode : routingNodes) {
                for (ShardRouting shardRoutingEntry : routingNode) {
                    // every relocating shard has a double entry, ignore the target one.
                    if (shardRoutingEntry.initializing() && shardRoutingEntry.relocatingNodeId() != null)
                        continue;

                    Index index = shardRoutingEntry.index();
                    IndexRoutingTable.Builder indexBuilder = indexRoutingTableBuilders.get(index.getName());
                    if (indexBuilder == null) {
                        indexBuilder = new IndexRoutingTable.Builder(index);
                        indexRoutingTableBuilders.put(index.getName(), indexBuilder);
                    }

                    indexBuilder.addShard(shardRoutingEntry);
                }
            }

            Iterable<ShardRouting> shardRoutingEntries = Iterables.concat(routingNodes.unassigned(), routingNodes.unassigned().ignored());

            for (ShardRouting shardRoutingEntry : shardRoutingEntries) {
                Index index = shardRoutingEntry.index();
                IndexRoutingTable.Builder indexBuilder = indexRoutingTableBuilders.get(index.getName());
                if (indexBuilder == null) {
                    indexBuilder = new IndexRoutingTable.Builder(index);
                    indexRoutingTableBuilders.put(index.getName(), indexBuilder);
                }
                indexBuilder.addShard(shardRoutingEntry);
            }

            for (IndexRoutingTable.Builder indexBuilder : indexRoutingTableBuilders.values()) {
                add(indexBuilder);
            }
            */
            return this;
        }"""

new = """        public Builder updateNodes(long version, RoutingNodes routingNodes) {
            // this is being called without pre initializing the routing table, so we must copy over the version as well
            this.version = version;

            Map<String, IndexRoutingTable.Builder> indexRoutingTableBuilders = new HashMap<>();
            for (RoutingNode routingNode : routingNodes) {
                for (ShardRouting shardRoutingEntry : routingNode) {
                    // every relocating shard has a double entry, ignore the target one.
                    if (shardRoutingEntry.initializing() && shardRoutingEntry.relocatingNodeId() != null) {
                        continue;
                    }
                    addShard(indexRoutingTableBuilders, shardRoutingEntry);
                }
            }

            Iterable<ShardRouting> shardRoutingEntries = Iterables.concat(routingNodes.unassigned(), routingNodes.unassigned().ignored());

            for (ShardRouting shardRoutingEntry : shardRoutingEntries) {
                addShard(indexRoutingTableBuilders, shardRoutingEntry);
            }

            for (IndexRoutingTable.Builder indexBuilder : indexRoutingTableBuilders.values()) {
                add(indexBuilder);
            }
            return this;
        }

        private static void addShard(
            final Map<String, IndexRoutingTable.Builder> indexRoutingTableBuilders,
            final ShardRouting shardRoutingEntry
        ) {
            Index index = shardRoutingEntry.index();
            IndexRoutingTable.Builder indexBuilder = indexRoutingTableBuilders.get(index.getName());
            if (indexBuilder == null) {
                indexBuilder = new IndexRoutingTable.Builder(index);
                indexRoutingTableBuilders.put(index.getName(), indexBuilder);
            }
            indexBuilder.addShard(shardRoutingEntry);
        }"""

if old not in t:
    print(
        "patch-opensearch-routing-table-for-os13: updateNodes commented block not found (already patched or different tree)",
        file=sys.stderr,
    )
    sys.exit(0)
path.write_text(t.replace(old, new, 1), encoding="utf-8")
print("Restored RoutingTable.Builder.updateNodes →", path)
PY
