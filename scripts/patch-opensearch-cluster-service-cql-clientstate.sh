#!/usr/bin/env bash
# ClusterService: CQL process(...) overloads with ClientState + getCassandraDiscovery for OpenSearchSingleNodeTestCase.
#
# Usage: ./scripts/patch-opensearch-cluster-service-cql-clientstate.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
CS="$DEST/server/src/main/java/org/opensearch/cluster/service/ClusterService.java"
[[ -f "$CS" ]] || exit 0

if grep -q 'private org.apache.cassandra.cql3.UntypedResultSet processWithQueryHandler(' "$CS" 2>/dev/null && grep -q 'getCassandraDiscovery()' "$CS" 2>/dev/null; then
  echo "ClusterService getCassandraDiscovery already present: $CS"
  exit 0
fi

python3 - "$CS" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

extra = """
    private org.apache.cassandra.cql3.UntypedResultSet processWithQueryHandler(
        org.apache.cassandra.db.ConsistencyLevel cl,
        org.apache.cassandra.db.ConsistencyLevel serialCl,
        org.apache.cassandra.service.ClientState clientState,
        String query,
        Object... values
    ) throws org.apache.cassandra.exceptions.RequestExecutionException,
             org.apache.cassandra.exceptions.RequestValidationException,
             org.apache.cassandra.exceptions.InvalidRequestException {
        org.apache.cassandra.cql3.QueryHandler handler = org.apache.cassandra.service.ClientState.getCQLQueryHandler();
        org.apache.cassandra.service.QueryState queryState = new org.apache.cassandra.service.QueryState(clientState);
        org.apache.cassandra.transport.messages.ResultMessage.Prepared prepared =
            handler.prepare(query, clientState, java.util.Collections.emptyMap());

        java.util.List<java.nio.ByteBuffer> boundValues = new java.util.ArrayList<>(values.length);
        for (int i = 0; i < values.length; i++) {
            Object value = values[i];
            org.apache.cassandra.db.marshal.AbstractType type = prepared.metadata.names.get(i).type;
            boundValues.add(
                value instanceof java.nio.ByteBuffer || value == null
                    ? (java.nio.ByteBuffer) value
                    : type.decompose(value)
            );
        }

        org.apache.cassandra.cql3.QueryOptions queryOptions =
            serialCl == null
                ? org.apache.cassandra.cql3.QueryOptions.forInternalCalls(cl, boundValues)
                : org.apache.cassandra.cql3.QueryOptions.forInternalCalls(cl, serialCl, boundValues);
        org.apache.cassandra.cql3.CQLStatement statement = handler.parse(query, queryState, queryOptions);
        org.apache.cassandra.transport.messages.ResultMessage result =
            handler.process(statement, queryState, queryOptions, java.util.Collections.emptyMap(), System.nanoTime());
        return result instanceof org.apache.cassandra.transport.messages.ResultMessage.Rows
            ? org.apache.cassandra.cql3.UntypedResultSet.create(
                ((org.apache.cassandra.transport.messages.ResultMessage.Rows) result).result
            )
            : null;
    }

    public org.apache.cassandra.cql3.UntypedResultSet process(
        org.apache.cassandra.db.ConsistencyLevel cl,
        org.apache.cassandra.service.ClientState clientState,
        final String query
    ) throws org.apache.cassandra.exceptions.RequestExecutionException,
             org.apache.cassandra.exceptions.RequestValidationException,
             org.apache.cassandra.exceptions.InvalidRequestException {
        return processWithQueryHandler(cl, null, clientState, query);
    }

    public org.apache.cassandra.cql3.UntypedResultSet process(
        org.apache.cassandra.db.ConsistencyLevel cl,
        org.apache.cassandra.service.ClientState clientState,
        final String query,
        Object... values
    ) throws org.apache.cassandra.exceptions.RequestExecutionException,
             org.apache.cassandra.exceptions.RequestValidationException,
             org.apache.cassandra.exceptions.InvalidRequestException {
        return processWithQueryHandler(cl, null, clientState, query, values);
    }

    public org.elassandra.discovery.CassandraDiscovery getCassandraDiscovery() {
        return null;
    }
"""

needle = """    public boolean processWriteConditional(
        org.apache.cassandra.db.ConsistencyLevel cl,
        org.apache.cassandra.db.ConsistencyLevel serialCl,
        final String query,
        Object... values
    ) throws org.apache.cassandra.exceptions.RequestExecutionException,
             org.apache.cassandra.exceptions.RequestValidationException,
             org.apache.cassandra.exceptions.InvalidRequestException {
        return false;
    }

}"""
if needle not in text:
    print("ClusterService: processWriteConditional tail not found", file=sys.stderr)
    sys.exit(1)
text = text.replace(needle, """    public boolean processWriteConditional(
        org.apache.cassandra.db.ConsistencyLevel cl,
        org.apache.cassandra.db.ConsistencyLevel serialCl,
        final String query,
        Object... values
    ) throws org.apache.cassandra.exceptions.RequestExecutionException,
             org.apache.cassandra.exceptions.RequestValidationException,
             org.apache.cassandra.exceptions.InvalidRequestException {
        return false;
    }
""" + extra + "\n}", 1)
path.write_text(text, encoding="utf-8")
print("Patched ClusterService ClientState process + getCassandraDiscovery →", path)
PY
