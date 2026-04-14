#!/usr/bin/env bash
# Restore Elassandra's delete-index Cassandra cleanup in the OpenSearch side-car.
# This makes `es.drop_on_delete_index=true` actually drop backing keyspaces/tables
# so embedded sidecar tests do not leak Cassandra state between methods.
#
# Usage: ./scripts/patch-opensearch-metadata-delete-index-elassandra-drop.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
MD="$DEST/server/src/main/java/org/opensearch/cluster/metadata/MetadataDeleteIndexService.java"
[[ -f "$MD" ]] || exit 0

python3 - "$MD" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

if (
    "class KeyspaceRemovalInfo" in text
    and "clusterService.getSchemaManager().dropIndexKeyspace" in text
    and "public SchemaUpdate schemaUpdate()" in text
    and '"index.drop_on_delete_index"' in text
    and '"cluster.drop_on_delete_index"' in text
):
    print("MetadataDeleteIndexService Cassandra drop cleanup already patched:", path)
    raise SystemExit(0)


def insert_after_once(source: str, anchor: str, insertion: str, label: str) -> str:
    if insertion in source:
        return source
    if anchor not in source:
        raise SystemExit(f"{path}: anchor not found for {label}")
    return source.replace(anchor, anchor + insertion, 1)


extra_imports = """import com.carrotsearch.hppc.cursors.ObjectCursor;
import com.google.common.collect.HashMultimap;
import org.apache.cassandra.db.Mutation;
import org.apache.cassandra.schema.ElassandraSchemaBridge;
import org.apache.cassandra.schema.KeyspaceMetadata;
import org.apache.cassandra.schema.TableMetadata;
import org.apache.cassandra.transport.Event;
import org.apache.cassandra.utils.FBUtilities;
import org.elassandra.cluster.SchemaManager;
import org.opensearch.cluster.ClusterStateTaskConfig.SchemaUpdate;
import org.opensearch.index.mapper.MapperService;

"""

text = insert_after_once(text, "package org.opensearch.cluster.metadata;\n\n", extra_imports, "extra imports")
text = insert_after_once(
    text,
    "import java.util.Arrays;\n",
    "import java.util.ArrayList;\nimport java.util.Collection;\n",
    "collection imports",
)

old_execute = """                @Override
                public ClusterState execute(final ClusterState currentState) {
                    return deleteIndices(currentState, Sets.newHashSet(request.indices()));
                }
"""

new_execute = """                @Override
                public SchemaUpdate schemaUpdate() {
                    return SchemaUpdate.UPDATE;
                }

                @Override
                public ClusterState execute(final ClusterState currentState) {
                    throw new UnsupportedOperationException();
                }

                @Override
                public ClusterState execute(
                    final ClusterState currentState,
                    Collection<Mutation> mutations,
                    Collection<Event.SchemaChange> events
                ) {
                    return deleteIndices(currentState, Sets.newHashSet(request.indices()), mutations, events);
                }
"""

if new_execute not in text:
    if old_execute not in text:
        raise SystemExit(f"{path}: anchor not found for state update task")
    text = text.replace(old_execute, new_execute, 1)

original_tail_marker = """    /**
     * Delete some indices from the cluster state.
     */
    public ClusterState deleteIndices(ClusterState currentState, Set<Index> indices) {
"""
patched_tail_marker = """    // for testing purposes only
    public ClusterState deleteIndices(ClusterState currentState, Set<Index> indices) {
"""

if patched_tail_marker in text:
    prefix = text[: text.index(patched_tail_marker)]
elif original_tail_marker in text:
    prefix = text[: text.index(original_tail_marker)]
else:
    raise SystemExit(f"{path}: anchor not found for deleteIndices tail")

new_tail = """    // for testing purposes only
    public ClusterState deleteIndices(ClusterState currentState, Set<Index> indices) {
        return deleteIndices(currentState, indices, new ArrayList<Mutation>(), new ArrayList<Event.SchemaChange>());
    }

    // collected keyspaces and tables for deleted indices
    class KeyspaceRemovalInfo {
        String keyspace;
        Set<IndexMetadata> indices = new HashSet<>();
        Set<String> droppableTables = new HashSet<>();
        Set<String> unindexableTables = new HashSet<>();
        boolean droppableKeyspace = true;

        KeyspaceRemovalInfo(String keyspace) {
            this.keyspace = keyspace;
        }

        void addRemovedIndex(IndexMetadata indexMetadata, boolean clusterDropOnDelete) {
            assert this.keyspace.equals(indexMetadata.keyspace()) : "Keyspace does not match";
            indices.add(indexMetadata);
            for (ObjectCursor<MappingMetadata> type : indexMetadata.getMappings().values()) {
                if (MapperService.DEFAULT_MAPPING.equals(type.value.type()) == false) {
                    String tableName = SchemaManager.typeToCfName(indexMetadata.keyspace(), type.value.type());
                    unindexableTables.add(tableName);
                    if (indexMetadata.getSettings().getAsBoolean("index.drop_on_delete_index", clusterDropOnDelete)) {
                        droppableTables.add(tableName);
                    }
                }
            }
            if (indexMetadata.getSettings().getAsBoolean("index.drop_on_delete_index", clusterDropOnDelete) == false) {
                droppableKeyspace = false;
            }
        }

        void removeUsedTables(IndexMetadata indexMetadata) {
            assert this.keyspace.equals(indexMetadata.keyspace()) : "Keyspace does not match";
            for (ObjectCursor<MappingMetadata> type : indexMetadata.getMappings().values()) {
                String tableName = SchemaManager.typeToCfName(indexMetadata.keyspace(), type.value.type());
                droppableTables.remove(tableName);
                unindexableTables.remove(tableName);
                droppableKeyspace = false;
            }
        }

        void drop(Collection<Mutation> mutations, Collection<Event.SchemaChange> events) {
            logger.debug(
                "drop keyspaces={} droppableKeyspace={} droppableTables={} unindexableTables={}",
                keyspace,
                droppableKeyspace,
                droppableTables,
                unindexableTables
            );

            if (droppableKeyspace) {
                clusterService.getSchemaManager().dropIndexKeyspace(keyspace, mutations, events);
                return;
            }

            KeyspaceMetadata ksm = SchemaManager.getKSMetaDataCopy(keyspace);
            if (ksm == null) {
                return;
            }

            for (String table : droppableTables) {
                ksm = clusterService.getSchemaManager().dropTable(ksm, table, mutations, events);
                unindexableTables.remove(table);
            }
            for (String table : unindexableTables) {
                clusterService.getSchemaManager().dropSecondaryIndex(ksm, table, mutations, events);
            }

            HashMultimap<String, IndexMetadata> tableExtensionToRemove = HashMultimap.create();
            for (IndexMetadata indexMetadata : indices) {
                for (ObjectCursor<MappingMetadata> type : indexMetadata.getMappings().values()) {
                    String table = SchemaManager.typeToCfName(indexMetadata.keyspace(), type.value.type());
                    if (droppableTables.contains(table) == false && unindexableTables.contains(table) == false) {
                        tableExtensionToRemove.put(table, indexMetadata);
                    }
                }
            }
            Mutation.SimpleBuilder builder = ElassandraSchemaBridge.makeCreateKeyspaceMutation(ksm, FBUtilities.timestampMicros());
            boolean removedExtension = false;
            for (String table : tableExtensionToRemove.keySet()) {
                TableMetadata cfm = ksm.getTableOrViewNullable(table);
                clusterService.getSchemaManager().removeTableExtensionToMutationBuilder(cfm, tableExtensionToRemove.get(table), builder);
                removedExtension = true;
            }
            if (removedExtension) {
                mutations.add(builder.build());
            }
        }
    }

    /**
     * Delete some indices from the cluster state.
     */
    public ClusterState deleteIndices(
        ClusterState currentState,
        Set<Index> indices,
        Collection<Mutation> mutations,
        Collection<Event.SchemaChange> events
    ) {
        final Metadata meta = currentState.metadata();
        final Set<Index> indicesToDelete = new HashSet<>();
        final Map<Index, DataStream> backingIndices = new HashMap<>();
        for (Index index : indices) {
            IndexMetadata indexMetadata = meta.getIndexSafe(index);
            IndexAbstraction.DataStream parent = meta.getIndicesLookup().get(indexMetadata.getIndex().getName()).getParentDataStream();
            if (parent != null) {
                if (parent.getWriteIndex().equals(indexMetadata)) {
                    throw new IllegalArgumentException(
                        "index ["
                            + index.getName()
                            + "] is the write index for data stream ["
                            + parent.getName()
                            + "] and cannot be deleted"
                    );
                } else {
                    backingIndices.put(index, parent.getDataStream());
                }
            }
            indicesToDelete.add(indexMetadata.getIndex());
        }

        Set<Index> snapshottingIndices = SnapshotsService.snapshottingIndices(currentState, indicesToDelete);
        if (snapshottingIndices.isEmpty() == false) {
            throw new SnapshotInProgressException(
                "Cannot delete indices that are being snapshotted: "
                    + snapshottingIndices
                    + ". Try again after snapshot finishes or cancel the currently running snapshot."
            );
        }

        RoutingTable.Builder routingTableBuilder = RoutingTable.builder(currentState.routingTable());
        Metadata.Builder metadataBuilder = Metadata.builder(meta);
        ClusterBlocks.Builder clusterBlocksBuilder = ClusterBlocks.builder().blocks(currentState.blocks());

        final IndexGraveyard.Builder graveyardBuilder = IndexGraveyard.builder(metadataBuilder.indexGraveyard());
        final int previousGraveyardSize = graveyardBuilder.tombstones().size();
        final boolean clusterDropOnDelete = currentState.metadata()
            .settings()
            .getAsBoolean("cluster.drop_on_delete_index", Boolean.getBoolean("es.drop_on_delete_index"));
        final Map<String, KeyspaceRemovalInfo> removalInfoMap = new HashMap<>();
        for (final Index index : indices) {
            String indexName = index.getName();
            logger.info("{} deleting index", index);
            routingTableBuilder.remove(indexName);
            clusterBlocksBuilder.removeIndexBlocks(indexName);
            metadataBuilder.remove(indexName);
            if (backingIndices.containsKey(index)) {
                DataStream parent = metadataBuilder.dataStream(backingIndices.get(index).getName());
                metadataBuilder.put(parent.removeBackingIndex(index));
            }

            final IndexMetadata indexMetadata = currentState.metadata().getIndexSafe(index);
            KeyspaceRemovalInfo removalInfo = removalInfoMap.computeIfAbsent(indexMetadata.keyspace(), KeyspaceRemovalInfo::new);
            removalInfo.addRemovedIndex(indexMetadata, clusterDropOnDelete);
        }
        final IndexGraveyard currentGraveyard = graveyardBuilder.addTombstones(indices).build(settings);
        metadataBuilder.indexGraveyard(currentGraveyard);
        logger.trace(
            "{} tombstones purged from the cluster state. Previous tombstone size: {}. Current tombstone size: {}.",
            graveyardBuilder.getNumPurged(),
            previousGraveyardSize,
            currentGraveyard.getTombstones().size()
        );

        Metadata newMetadata = metadataBuilder.build();
        ClusterBlocks blocks = clusterBlocksBuilder.build();

        for (ObjectCursor<IndexMetadata> cursor : newMetadata.indices().values()) {
            final IndexMetadata indexMetadata = cursor.value;
            removalInfoMap.computeIfPresent(indexMetadata.keyspace(), (keyspace, removalInfo) -> {
                removalInfo.removeUsedTables(indexMetadata);
                return removalInfo;
            });
        }
        for (KeyspaceRemovalInfo removalInfo : removalInfoMap.values()) {
            removalInfo.drop(mutations, events);
        }

        ImmutableOpenMap<String, ClusterState.Custom> customs = currentState.getCustoms();
        final RestoreInProgress restoreInProgress = currentState.custom(RestoreInProgress.TYPE, RestoreInProgress.EMPTY);
        RestoreInProgress updatedRestoreInProgress = RestoreService.updateRestoreStateWithDeletedIndices(restoreInProgress, indices);
        if (updatedRestoreInProgress != restoreInProgress) {
            ImmutableOpenMap.Builder<String, ClusterState.Custom> builder = ImmutableOpenMap.builder(customs);
            builder.put(RestoreInProgress.TYPE, updatedRestoreInProgress);
            customs = builder.build();
        }

        return allocationService.reroute(
            ClusterState.builder(currentState)
                .routingTable(routingTableBuilder.build())
                .metadata(newMetadata)
                .blocks(blocks)
                .customs(customs)
                .build(),
            "deleted indices [" + indices + "]"
        );
    }
}
"""

path.write_text(prefix + new_tail, encoding="utf-8")
print("Patched MetadataDeleteIndexService Cassandra cleanup:", path)
PY
