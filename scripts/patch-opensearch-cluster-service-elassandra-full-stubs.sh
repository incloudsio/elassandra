#!/usr/bin/env bash
# Extended Elassandra ClusterService compile stubs (SchemaListener, routing, gateway, daemon).
# Run after patch-opensearch-cluster-service-elassandra-stubs.sh and schema-stubs.
#
# Usage: ./scripts/patch-opensearch-cluster-service-elassandra-full-stubs.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
CS="$DEST/server/src/main/java/org/opensearch/cluster/service/ClusterService.java"
[[ -f "$CS" ]] || exit 0

python3 - "$CS" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
if "public org.opensearch.cluster.metadata.Metadata.Builder mergeIndexMetaData(" in text:
    print("ClusterService full stubs already present:", path)
    raise SystemExit(0)

marker = """    public java.util.UUID readMetaDataOwner(long version) {
        return null;
    }

    private static final java.util.regex.Pattern INDEX_TO_NAME_PATTERN = java.util.regex.Pattern.compile("\\\\.|\\\\-");

    public static String indexToKsName(String index) {
        return INDEX_TO_NAME_PATTERN.matcher(index).replaceAll("_");
    }

    /** Elassandra replication factor helper (CQL keyspace name). */
    public static int replicationFactor(String keyspace) {
        return 1;
    }"""
if marker not in text:
    print("patch: readMetaDataOwner+indexToKsName+replicationFactor block not found", file=sys.stderr)
    sys.exit(1)

insert = """    public java.util.UUID readMetaDataOwner(long version) {
        return null;
    }

    public org.opensearch.cluster.metadata.Metadata.Builder mergeIndexMetaData(
        org.opensearch.cluster.metadata.Metadata.Builder metaDataBuilder,
        String indexName,
        java.util.List<org.opensearch.cluster.metadata.IndexMetadata> mappings
    ) {
        return metaDataBuilder;
    }

    public org.opensearch.cluster.metadata.Metadata.Builder mergeWithTableExtensions(
        org.opensearch.cluster.metadata.Metadata.Builder metaDataBuilder
    ) {
        return metaDataBuilder;
    }

    public org.opensearch.cluster.metadata.Metadata addVirtualIndexMappings(
        org.opensearch.cluster.metadata.Metadata metaData
    ) {
        return metaData;
    }

    public org.opensearch.cluster.metadata.Metadata readMetaData(
        org.apache.cassandra.schema.TableMetadata cfm
    ) {
        return null;
    }

    public void submitNumberOfShardsAndReplicasUpdate(String source, String keyspace) {
    }

    public String getElasticAdminKeyspaceName() {
        return "elastic_admin";
    }

    public static final String ELASTIC_ADMIN_METADATA_TABLE = "metadata_log";

    public boolean isValidExtensionKey(String key) {
        return key != null && key.startsWith("elasticsearch_mapping");
    }

    public org.opensearch.cluster.metadata.IndexMetadata getIndexMetaDataFromExtension(
        java.nio.ByteBuffer value
    ) {
        return null;
    }

    public org.elassandra.cluster.routing.PrimaryFirstSearchStrategy.PrimaryFirstRouter updateRouter(
        org.opensearch.cluster.metadata.IndexMetadata indexMetadata,
        org.opensearch.cluster.ClusterState state
    ) {
        return null;
    }

    public org.elassandra.cluster.routing.AbstractSearchStrategy.Router getRouter(
        org.opensearch.cluster.metadata.IndexMetadata indexMetadata,
        org.opensearch.cluster.ClusterState state
    ) {
        return null;
    }

    public void publishShardRoutingState(
        String index,
        org.opensearch.cluster.routing.ShardRoutingState shardRoutingState
    ) throws java.io.IOException {
    }

    public void publishX1() throws java.io.IOException {
    }

    public static String getElasticsearchClusterName(org.opensearch.common.settings.Settings settings) {
        return org.apache.cassandra.config.DatabaseDescriptor.getClusterName();
    }

    public boolean hasMetaDataTable() {
        org.apache.cassandra.schema.KeyspaceMetadata ksm = org.apache.cassandra.schema.Schema.instance.getKeyspaceMetadata(getElasticAdminKeyspaceName());
        return ksm != null && ksm.getTableOrViewNullable(ELASTIC_ADMIN_METADATA_TABLE) != null;
    }

    /** Block until local shards are started ({@link CassandraShardStartedBarrier}). */
    public void blockUntilShardsStarted() {
    }

    public static final String SETTING_SYSTEM_TOKEN_RANGES_QUERY_EXPIRE = "es.token_ranges_query_expire_minutes";

    public static String buildIndexName(String cfsName) {
        return cfsName;
    }

    private static final java.util.regex.Pattern INDEX_TO_NAME_PATTERN = java.util.regex.Pattern.compile("\\\\.|\\\\-");

    public static String indexToKsName(String index) {
        return INDEX_TO_NAME_PATTERN.matcher(index).replaceAll("_");
    }

    /** Elassandra replication factor helper (CQL keyspace name). */
    public static int replicationFactor(String keyspace) {
        return 1;
    }"""

path.write_text(text.replace(marker, insert, 1), encoding="utf-8")
print("ClusterService full stubs OK →", path)
PY
