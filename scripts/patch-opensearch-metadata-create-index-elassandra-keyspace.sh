#!/usr/bin/env bash
# Restore Elassandra create-index keyspace bootstrap in the OpenSearch side-car:
# always create/update the backing Cassandra keyspace and preserve index.replication
# even when the index has no non-default mapping yet.
#
# Usage: ./scripts/patch-opensearch-metadata-create-index-elassandra-keyspace.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
MD="$DEST/server/src/main/java/org/opensearch/cluster/metadata/MetadataCreateIndexService.java"
[[ -f "$MD" ]] || exit 0

python3 - "$MD" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

if "IndexMetadata.INDEX_SETTING_REPLICATION_SETTING.get(indexMetadata.getSettings())" in text:
    print("MetadataCreateIndexService keyspace bootstrap already patched:", path)
    raise SystemExit(0)

old = """            final DocumentMapper documentMapper = indexService.mapperService().documentMapper();
            if (documentMapper != null && MapperService.DEFAULT_MAPPING.equals(documentMapper.type()) == false) {
                List<Mutation> mutations = new LinkedList<>();
                List<Event.SchemaChange> events = new LinkedList<>();
                KeyspaceMetadata ksm = clusterService.getSchemaManager().createOrUpdateKeyspace(
                    indexMetadata.keyspace(),
                    indexMetadata.getNumberOfReplicas() + 1,
                    Collections.emptyMap(),
                    mutations,
                    events
                );
                clusterService.getSchemaManager().updateTableSchema(
                    ksm,
                    documentMapper.type(),
                    Collections.singletonMap(indexMetadata.getIndex(), Pair.create(indexMetadata, indexService.mapperService())),
                    mutations,
                    events
                );
                if (mutations.isEmpty() == false) {
                    MigrationManager.mergeSchema(mutations, clusterService.getSchemaManager().getInhibitedSchemaListeners());
                }
            }
"""

new = """            final DocumentMapper documentMapper = indexService.mapperService().documentMapper();
            List<Mutation> mutations = new LinkedList<>();
            List<Event.SchemaChange> events = new LinkedList<>();
            java.util.Map<String, Integer> replication = new java.util.LinkedHashMap<>();
            for (String entry : IndexMetadata.INDEX_SETTING_REPLICATION_SETTING.get(indexMetadata.getSettings())) {
                int colon = entry.indexOf(':');
                replication.put(entry.substring(0, colon), Integer.parseInt(entry.substring(colon + 1)));
            }
            KeyspaceMetadata ksm = clusterService.getSchemaManager().createOrUpdateKeyspace(
                indexMetadata.keyspace(),
                indexMetadata.getNumberOfReplicas() + 1,
                replication,
                mutations,
                events
            );
            if (documentMapper != null && MapperService.DEFAULT_MAPPING.equals(documentMapper.type()) == false) {
                clusterService.getSchemaManager().updateTableSchema(
                    ksm,
                    documentMapper.type(),
                    Collections.singletonMap(indexMetadata.getIndex(), Pair.create(indexMetadata, indexService.mapperService())),
                    mutations,
                    events
                );
            }
            if (mutations.isEmpty() == false) {
                MigrationManager.mergeSchema(mutations, clusterService.getSchemaManager().getInhibitedSchemaListeners());
            }
"""

if old not in text:
    print("MetadataCreateIndexService anchor not found", file=sys.stderr)
    raise SystemExit(1)

path.write_text(text.replace(old, new, 1), encoding="utf-8")
print("Patched MetadataCreateIndexService create-index keyspace bootstrap:", path)
PY
