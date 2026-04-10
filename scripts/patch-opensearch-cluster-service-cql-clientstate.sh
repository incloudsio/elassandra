#!/usr/bin/env bash
# ClusterService: CQL process(...) overloads with ClientState + getCassandraDiscovery for OpenSearchSingleNodeTestCase.
#
# Usage: ./scripts/patch-opensearch-cluster-service-cql-clientstate.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
CS="$DEST/server/src/main/java/org/opensearch/cluster/service/ClusterService.java"
[[ -f "$CS" ]] || exit 0

if grep -q 'getCassandraDiscovery()' "$CS" 2>/dev/null; then
  echo "ClusterService getCassandraDiscovery already present: $CS"
  exit 0
fi

python3 - "$CS" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

extra = """
    public org.apache.cassandra.cql3.UntypedResultSet process(
        org.apache.cassandra.db.ConsistencyLevel cl,
        org.apache.cassandra.service.ClientState clientState,
        final String query
    ) throws org.apache.cassandra.exceptions.RequestExecutionException,
             org.apache.cassandra.exceptions.RequestValidationException,
             org.apache.cassandra.exceptions.InvalidRequestException {
        return process(cl, query);
    }

    public org.apache.cassandra.cql3.UntypedResultSet process(
        org.apache.cassandra.db.ConsistencyLevel cl,
        org.apache.cassandra.service.ClientState clientState,
        final String query,
        Object... values
    ) throws org.apache.cassandra.exceptions.RequestExecutionException,
             org.apache.cassandra.exceptions.RequestValidationException,
             org.apache.cassandra.exceptions.InvalidRequestException {
        return process(cl, query, values);
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
