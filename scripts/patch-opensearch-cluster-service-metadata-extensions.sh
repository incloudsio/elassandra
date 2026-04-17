#!/usr/bin/env bash
# Replace ClusterService metadata/extension compile stubs with sidecar runtime implementations
# needed by CassandraDiscoveryTests and downstream schema/index persistence flows.
#
# Usage: ./scripts/patch-opensearch-cluster-service-metadata-extensions.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
CS="$DEST/server/src/main/java/org/opensearch/cluster/service/ClusterService.java"
[[ -f "$CS" ]] || exit 0

python3 - "$CS" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

def replace_one(text, candidates, new):
    for candidate in candidates:
        if candidate in text:
            return text.replace(candidate, new, 1)
    if new in text or new.strip() in text:
        return text
    print(f"patch anchor not found in {path}:\\n{candidates[0]}", file=sys.stderr)
    raise SystemExit(1)

text = replace_one(
    text,
    ["""    public String getExtensionKey(org.opensearch.cluster.metadata.IndexMetadata indexMetaData) {
        return indexMetaData.getIndex().getName();
    }
"""],
    """    public String getExtensionKey(org.opensearch.cluster.metadata.IndexMetadata indexMetaData) {
        return getElasticAdminKeyspaceName() + "/" + indexMetaData.getIndex().getName();
    }
""",
)

text = replace_one(
    text,
    ["""    public void putIndexMetaDataExtension(
        org.opensearch.cluster.metadata.IndexMetadata indexMetaData,
        java.util.Map<String, java.nio.ByteBuffer> extensions
    ) {
    }
""",
     """    public void putIndexMetaDataExtension(
        org.opensearch.cluster.metadata.IndexMetadata indexMetaData,
        java.util.Map<String, java.nio.ByteBuffer> extensions
    ) {
        try {
            org.opensearch.common.xcontent.XContentBuilder builder = org.opensearch.common.xcontent.XContentFactory.jsonBuilder();
            builder.startObject();
            org.opensearch.cluster.metadata.IndexMetadata.Builder.toXContent(
                indexMetaData,
                builder,
                org.opensearch.common.xcontent.ToXContent.EMPTY_PARAMS
            );
            builder.endObject();
            extensions.put(
                getExtensionKey(indexMetaData),
                java.nio.ByteBuffer.wrap(
                    org.opensearch.common.bytes.BytesReference.toBytes(
                        org.opensearch.common.bytes.BytesReference.bytes(builder)
                    )
                )
            );
        } catch (java.io.IOException e) {
            throw new org.opensearch.OpenSearchException("Failed to serialize index metadata", e);
        }
    }
"""],
    """    public void putIndexMetaDataExtension(
        org.opensearch.cluster.metadata.IndexMetadata indexMetaData,
        java.util.Map<String, java.nio.ByteBuffer> extensions
    ) {
        try {
            java.util.Map<String, String> params = new java.util.HashMap<>();
            params.put("binary", "true");
            params.put(
                org.opensearch.cluster.metadata.Metadata.CONTEXT_MODE_PARAM,
                org.opensearch.cluster.metadata.Metadata.CONTEXT_MODE_GATEWAY
            );
            org.opensearch.common.xcontent.XContentBuilder builder =
                org.opensearch.common.xcontent.XContentFactory.contentBuilder(org.opensearch.common.xcontent.XContentType.SMILE);
            builder.startObject();
            org.opensearch.cluster.metadata.IndexMetadata.Builder.toXContent(
                indexMetaData,
                builder,
                new org.opensearch.common.xcontent.ToXContent.MapParams(params)
            );
            builder.endObject();
            extensions.put(
                getExtensionKey(indexMetaData),
                java.nio.ByteBuffer.wrap(
                    org.opensearch.common.bytes.BytesReference.toBytes(
                        org.opensearch.common.bytes.BytesReference.bytes(builder)
                    )
                )
            );
        } catch (java.io.IOException e) {
            throw new org.opensearch.OpenSearchException("Failed to serialize index metadata", e);
        }
    }
""",
)

commit_metadata_pattern = re.compile(
    r"""    public void commitMetaData\(
.*?
    \}
(?=
    public java.util.UUID readMetaDataOwner)""",
    re.DOTALL,
)
commit_metadata_replacement = """    public void commitMetaData(
        org.opensearch.cluster.metadata.Metadata oldMetaData,
        org.opensearch.cluster.metadata.Metadata newMetaData,
        String source
    ) throws org.elassandra.ConcurrentMetaDataUpdateException, org.apache.cassandra.exceptions.UnavailableException, java.io.IOException {
        if (newMetaData.clusterUUID().equals(localNode().getId()) == false) {
            return;
        }
        if (newMetaData.clusterUUID().equals(state().metadata().clusterUUID()) && newMetaData.version() < state().metadata().version()) {
            return;
        }
        final java.util.UUID owner = localNode().uuid();
        final String updateMetaDataQuery = String.format(
            java.util.Locale.ROOT,
            "UPDATE \\\"%s\\\".\\\"%s\\\" SET owner = ?, version = ?, source = ?, ts = dateOf(now()) "
                + "WHERE cluster_name = ? AND v = ? IF version = ?",
            getElasticAdminKeyspaceName(),
            ELASTIC_ADMIN_METADATA_TABLE
        );
        final String selectVersionQuery = String.format(
            java.util.Locale.ROOT,
            "SELECT version FROM \\\"%s\\\".\\\"%s\\\" WHERE cluster_name = ? LIMIT 1",
            getElasticAdminKeyspaceName(),
            ELASTIC_ADMIN_METADATA_TABLE
        );
        boolean applied = processWriteConditional(
            org.apache.cassandra.db.ConsistencyLevel.QUORUM,
            org.apache.cassandra.db.ConsistencyLevel.SERIAL,
            updateMetaDataQuery,
            owner,
            newMetaData.version(),
            source,
            org.apache.cassandra.config.DatabaseDescriptor.getClusterName(),
            newMetaData.version(),
            newMetaData.version() - 1
        );
        if (applied == false) {
            try {
                org.apache.cassandra.cql3.UntypedResultSet current = processWithQueryHandler(
                    org.apache.cassandra.db.ConsistencyLevel.SERIAL,
                    null,
                    org.apache.cassandra.service.ClientState.forInternalCalls(),
                    selectVersionQuery,
                    org.apache.cassandra.config.DatabaseDescriptor.getClusterName()
                );
                if (current != null && current.isEmpty() == false) {
                    long persistedVersion = current.one().getLong("version");
                    if (persistedVersion == newMetaData.version()) {
                        java.util.UUID persistedOwner = readMetaDataOwner(newMetaData.version());
                        if (owner.equals(persistedOwner)) {
                            applied = true;
                        }
                    } else if (persistedVersion <= oldMetaData.version()) {
                        applied = processWriteConditional(
                            org.apache.cassandra.db.ConsistencyLevel.QUORUM,
                            org.apache.cassandra.db.ConsistencyLevel.SERIAL,
                            updateMetaDataQuery,
                            owner,
                            newMetaData.version(),
                            source,
                            org.apache.cassandra.config.DatabaseDescriptor.getClusterName(),
                            newMetaData.version(),
                            persistedVersion
                        );
                    }
                }
            } catch (
                org.apache.cassandra.exceptions.RequestExecutionException
                    | org.apache.cassandra.exceptions.RequestValidationException e
            ) {
                throw new org.opensearch.OpenSearchException("Failed to reconcile metadata log version", e);
            }
        }
        if (applied == false) {
            java.util.UUID persistedOwner = readMetaDataOwner(newMetaData.version());
            if (owner.equals(persistedOwner)) {
                applied = true;
            }
        }
        if (applied == false) {
            throw new org.elassandra.ConcurrentMetaDataUpdateException(owner, newMetaData.version());
        }
    }
"""
match = commit_metadata_pattern.search(text)
if match is None:
    print(f"patch anchor not found in {path}: commitMetaData method", file=sys.stderr)
    raise SystemExit(1)
if commit_metadata_replacement.strip() not in text:
    text = text[:match.start()] + commit_metadata_replacement + text[match.end():]

text = replace_one(
    text,
    [
        """    public java.util.UUID readMetaDataOwner(long version) {
        return null;
    }
""",
        """    public java.util.UUID readMetaDataOwner(long version) {
        final String selectOwnerMetadataQuery = String.format(
            java.util.Locale.ROOT,
            "SELECT owner FROM \\"%s\\".\\"%s\\" WHERE cluster_name = ? AND v = ?",
            getElasticAdminKeyspaceName(),
            ELASTIC_ADMIN_METADATA_TABLE
        );
        final int attempts = Integer.getInteger("elassandra.metadata.read.attempts", 10);
        for (int i = 0; i < attempts; i++) {
            try {
                org.apache.cassandra.cql3.UntypedResultSet rs = processWithQueryHandler(
                    org.apache.cassandra.db.ConsistencyLevel.SERIAL,
                    null,
                    org.apache.cassandra.service.ClientState.forInternalCalls(),
                    selectOwnerMetadataQuery,
                    org.apache.cassandra.config.DatabaseDescriptor.getClusterName(),
                    version
                );
                if (rs != null && rs.isEmpty() == false) {
                    return rs.one().getUUID("owner");
                }
            } catch (org.apache.cassandra.exceptions.RequestTimeoutException e) {
                logger.warn("SERIAL read failed: {}", e.getMessage());
            } catch (org.apache.cassandra.exceptions.RequestExecutionException
                | org.apache.cassandra.exceptions.RequestValidationException
                | org.apache.cassandra.exceptions.InvalidRequestException e) {
                throw new org.opensearch.OpenSearchException("Failed to read metadata owner for version=" + version, e);
            }
        }
        return null;
    }
""",
    ],
    """    public java.util.UUID readMetaDataOwner(long version) {
        final String selectOwnerMetadataQuery = String.format(
            java.util.Locale.ROOT,
            "SELECT owner FROM \\"%s\\".\\"%s\\" WHERE cluster_name = ? AND v = ?",
            getElasticAdminKeyspaceName(),
            ELASTIC_ADMIN_METADATA_TABLE
        );
        final int attempts = Integer.getInteger("elassandra.metadata.read.attempts", 10);
        for (int i = 0; i < attempts; i++) {
            try {
                org.apache.cassandra.cql3.UntypedResultSet rs = processWithQueryHandler(
                    org.apache.cassandra.db.ConsistencyLevel.SERIAL,
                    null,
                    org.apache.cassandra.service.ClientState.forInternalCalls(),
                    selectOwnerMetadataQuery,
                    getElasticsearchClusterName(settings),
                    version
                );
                if (rs != null && rs.isEmpty() == false) {
                    return rs.one().getUUID("owner");
                }
            } catch (org.apache.cassandra.exceptions.RequestTimeoutException e) {
                // Retry SERIAL reads: a timeout here leaves no better recovery path for metadata CAS ownership checks.
            } catch (org.apache.cassandra.exceptions.RequestExecutionException
                | org.apache.cassandra.exceptions.RequestValidationException e) {
                throw new org.opensearch.OpenSearchException("Failed to read metadata owner for version=" + version, e);
            }
        }
        return null;
    }
""",
)

text = replace_one(
    text,
    ["""    public boolean isValidExtensionKey(String extensionName) {
        return extensionName != null && extensionName.contains("/");
    }
"""],
    """    public boolean isValidExtensionKey(String extensionName) {
        return extensionName != null && extensionName.startsWith(getElasticAdminKeyspaceName() + "/");
    }
""",
)

text = replace_one(
    text,
    ["""    public org.opensearch.cluster.metadata.IndexMetadata getIndexMetaDataFromExtension(java.nio.ByteBuffer value) {
        return org.opensearch.cluster.metadata.IndexMetadata.builder("__extension__").numberOfShards(1).numberOfReplicas(0).build();
    }
""",
     """    public org.opensearch.cluster.metadata.IndexMetadata getIndexMetaDataFromExtension(
        java.nio.ByteBuffer value
    ) {
        return null;
    }
""",
     """    public org.opensearch.cluster.metadata.IndexMetadata getIndexMetaDataFromExtension(java.nio.ByteBuffer value) {
        try (
            org.opensearch.common.xcontent.XContentParser parser = org.opensearch.common.xcontent.XContentType.JSON.xContent().createParser(
                org.opensearch.common.xcontent.NamedXContentRegistry.EMPTY,
                org.opensearch.common.xcontent.DeprecationHandler.THROW_UNSUPPORTED_OPERATION,
                org.apache.cassandra.utils.ByteBufferUtil.getArray(value)
            )
        ) {
            parser.nextToken();
            return org.opensearch.cluster.metadata.IndexMetadata.fromXContent(parser);
        } catch (java.io.IOException e) {
            throw new org.opensearch.OpenSearchException("Failed to deserialize index metadata", e);
        }
    }
"""],
    """    public org.opensearch.cluster.metadata.IndexMetadata getIndexMetaDataFromExtension(java.nio.ByteBuffer value) {
        try (
            org.opensearch.common.xcontent.XContentParser parser = org.opensearch.common.xcontent.XContentType.SMILE.xContent().createParser(
                org.opensearch.common.xcontent.NamedXContentRegistry.EMPTY,
                org.opensearch.common.xcontent.DeprecationHandler.THROW_UNSUPPORTED_OPERATION,
                org.apache.cassandra.utils.ByteBufferUtil.getArray(value)
            )
        ) {
            parser.nextToken();
            return org.opensearch.cluster.metadata.IndexMetadata.Builder.fromXContent(parser);
        } catch (java.io.IOException e) {
            throw new org.opensearch.OpenSearchException("Failed to deserialize index metadata", e);
        }
    }
""",
)

text = replace_one(
    text,
    ["""    public boolean processWriteConditional(
        org.apache.cassandra.db.ConsistencyLevel cl,
        org.apache.cassandra.db.ConsistencyLevel serialCl,
        String query,
        Object... values
    ) throws org.apache.cassandra.exceptions.RequestExecutionException,
             org.apache.cassandra.exceptions.RequestValidationException,
             org.apache.cassandra.exceptions.InvalidRequestException {
        processWithQueryHandler(cl, serialCl, org.apache.cassandra.service.ClientState.forInternalCalls(), query, values);
        return true;
    }
""",
     """    public boolean processWriteConditional(
        org.apache.cassandra.db.ConsistencyLevel cl,
        org.apache.cassandra.db.ConsistencyLevel serialCl,
        final String query,
        Object... values
    ) throws org.apache.cassandra.exceptions.RequestExecutionException,
             org.apache.cassandra.exceptions.RequestValidationException,
             org.apache.cassandra.exceptions.InvalidRequestException {
        return false;
    }
"""],
    """    public boolean processWriteConditional(
        org.apache.cassandra.db.ConsistencyLevel cl,
        org.apache.cassandra.db.ConsistencyLevel serialCl,
        String query,
        Object... values
    ) throws org.apache.cassandra.exceptions.RequestExecutionException,
             org.apache.cassandra.exceptions.RequestValidationException,
             org.apache.cassandra.exceptions.InvalidRequestException {
        org.apache.cassandra.cql3.UntypedResultSet result =
            processWithQueryHandler(cl, serialCl, org.apache.cassandra.service.ClientState.forInternalCalls(), query, values);
        if (serialCl == null) {
            return true;
        }
        if (result != null && result.isEmpty() == false) {
            org.apache.cassandra.cql3.UntypedResultSet.Row row = result.one();
            if (row.has("[applied]")) {
                return row.getBoolean("[applied]");
            }
        }
        return false;
    }
""",
)

path.write_text(text, encoding="utf-8")
print("Patched ClusterService metadata CAS + extension runtime →", path)
PY
