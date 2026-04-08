#!/usr/bin/env bash
# ClusterService: CQL process(ConsistencyLevel, String, Object...) for QueryManager (fork parity).
#
# Usage: ./scripts/patch-opensearch-cluster-service-elassandra-cql-process.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
CS="$DEST/server/src/main/java/org/opensearch/cluster/service/ClusterService.java"
[[ -f "$CS" ]] || exit 0

if grep -q 'Elassandra: CQL process' "$CS"; then
  echo "ClusterService CQL process already patched: $CS"
  exit 0
fi

python3 - "$CS" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

method = """
    /**
     * Elassandra: CQL process (fork parity). Delegates to Cassandra {@code QueryProcessor} for side-car compile.
     */
    public org.apache.cassandra.cql3.UntypedResultSet process(
        org.apache.cassandra.db.ConsistencyLevel cl,
        String query,
        Object... values
    ) throws org.apache.cassandra.exceptions.RequestExecutionException,
             org.apache.cassandra.exceptions.RequestValidationException,
             org.apache.cassandra.exceptions.InvalidRequestException {
        return org.apache.cassandra.cql3.QueryProcessor.executeOnceInternal(query, values);
    }
"""

# Prefer inserting before the final closing brace of the class (after side-car stubs / SETTING_SYSTEM_SYNCHRONOUS_REFRESH).
if "QueryProcessor.executeOnceInternal" in text:
    print("ClusterService already has QueryProcessor delegation:", path)
    raise SystemExit(0)

if "SETTING_SYSTEM_SYNCHRONOUS_REFRESH" in text:
    needle = '    public static final String SETTING_SYSTEM_SYNCHRONOUS_REFRESH = "es.synchronous_refresh";\n}'
    if needle not in text:
        print("ClusterService: SETTING_SYSTEM_SYNCHRONOUS_REFRESH tail not found", file=sys.stderr)
        sys.exit(1)
    text = text.replace(needle, '    public static final String SETTING_SYSTEM_SYNCHRONOUS_REFRESH = "es.synchronous_refresh";' + method + "\n}", 1)
else:
    needle = """    public static int replicationFactor(String keyspace) {
        return 1;
    }
}"""
    if needle not in text:
        print("ClusterService: replicationFactor tail not found", file=sys.stderr)
        sys.exit(1)
    text = text.replace(needle, """    public static int replicationFactor(String keyspace) {
        return 1;
    }""" + method + "\n}", 1)

path.write_text(text, encoding="utf-8")
print("Patched", path)
PY
