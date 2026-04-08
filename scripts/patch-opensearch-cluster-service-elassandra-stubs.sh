#!/usr/bin/env bash
# Append Elassandra-only ClusterService APIs as compile-time stubs on stock OpenSearch ClusterService.
# Full behaviour requires merging the Elassandra fork of ClusterService (see OPENSEARCH_PORT.md).
#
# Usage: ./scripts/patch-opensearch-cluster-service-elassandra-stubs.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
CS="$DEST/server/src/main/java/org/opensearch/cluster/service/ClusterService.java"
if [[ ! -f "$CS" ]]; then
  echo "No ClusterService.java at $CS" >&2
  exit 1
fi

python3 - "$CS" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

has_rf = "public static int replicationFactor(String keyspace)" in text
has_ks = "public static String indexToKsName(String index)" in text
if has_rf and has_ks:
    print("ClusterService already has indexToKsName + replicationFactor stubs:", path)
    raise SystemExit(0)

INDEX_TO_KS_STUB = """    private static final java.util.regex.Pattern INDEX_TO_NAME_PATTERN = java.util.regex.Pattern.compile("\\\\.|\\\\-");

    public static String indexToKsName(String index) {
        return INDEX_TO_NAME_PATTERN.matcher(index).replaceAll("_");
    }

"""

RF_STUB = """    /** Elassandra replication factor helper (CQL keyspace name). */
    public static int replicationFactor(String keyspace) {
        return 1;
    }

    /** System property for synchronous refresh (see ElassandraIndexSettings / ElasticSecondaryIndex). */
    public static final String SETTING_SYSTEM_SYNCHRONOUS_REFRESH = "es.synchronous_refresh";
"""

if has_rf and not has_ks:
    marker = "    /** Elassandra replication factor helper"
    if marker not in text:
        print("patch: cannot insert indexToKsName (marker missing)", file=sys.stderr)
        raise SystemExit(1)
    text = text.replace(marker, INDEX_TO_KS_STUB + marker, 1)
    path.write_text(text, encoding="utf-8")
    print("Added indexToKsName stub:", path)
    raise SystemExit(0)

if "// --- Elassandra side-car compile stubs" in text:
    if "public java.util.UUID readMetaDataOwner(long version)" not in text:
        print("unexpected stub section in ClusterService", file=sys.stderr)
        raise SystemExit(1)
    text = text.replace(
        """    public java.util.UUID readMetaDataOwner(long version) {
        return null;
    }
}""",
        """    public java.util.UUID readMetaDataOwner(long version) {
        return null;
    }

""" + INDEX_TO_KS_STUB + RF_STUB + """}""",
        1,
    )
    path.write_text(text, encoding="utf-8")
    print("Added indexToKsName + replicationFactor stubs:", path)
    raise SystemExit(0)

needle = """    public <T> void submitStateUpdateTasks(
        final String source,
        final Map<T, ClusterStateTaskListener> tasks,
        final ClusterStateTaskConfig config,
        final ClusterStateTaskExecutor<T> executor
    ) {
        masterService.submitStateUpdateTasks(source, tasks, config, executor);
    }
}"""
stub_tail = (
    """    public <T> void submitStateUpdateTasks(
        final String source,
        final Map<T, ClusterStateTaskListener> tasks,
        final ClusterStateTaskConfig config,
        final ClusterStateTaskExecutor<T> executor
    ) {
        masterService.submitStateUpdateTasks(source, tasks, config, executor);
    }

    // --- Elassandra side-car compile stubs (no runtime behaviour; full port replaces these) ---

    public void setDiscovery(org.opensearch.discovery.Discovery discovery) {
    }

    public org.opensearch.indices.IndicesService getIndicesService() {
        return null;
    }

    public org.opensearch.index.IndexService indexServiceSafe(org.opensearch.index.Index index) {
        return null;
    }

    public org.elassandra.cluster.SchemaManager getSchemaManager() {
        return null;
    }

    public void writeMetadataToSchemaMutations(
        org.opensearch.cluster.metadata.Metadata metadata,
        java.util.Collection<org.apache.cassandra.db.Mutation> mutations,
        java.util.Collection<org.apache.cassandra.transport.Event.SchemaChange> events
    ) throws org.apache.cassandra.exceptions.ConfigurationException, java.io.IOException {
    }

    public void commitMetaData(
        org.opensearch.cluster.metadata.Metadata oldMetaData,
        org.opensearch.cluster.metadata.Metadata newMetaData,
        String source
    ) throws org.elassandra.ConcurrentMetaDataUpdateException, org.apache.cassandra.exceptions.UnavailableException, java.io.IOException {
    }

    public java.util.UUID readMetaDataOwner(long version) {
        return null;
    }

"""
    + INDEX_TO_KS_STUB
    + RF_STUB
    + "}"
)
if needle not in text:
    print("patch: ClusterService tail not found (file changed?)", file=sys.stderr)
    raise SystemExit(1)
path.write_text(text.replace(needle, stub_tail, 1), encoding="utf-8")
print("Appended Elassandra stubs:", path)
PY

echo "ClusterService Elassandra stubs OK → $CS"
