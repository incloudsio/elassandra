#!/usr/bin/env bash
# ClusterService#processWriteConditional (Cassandra PAXOS path) for QueryManager.
#
# Usage: ./scripts/patch-opensearch-cluster-service-process-write-conditional.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
CS="$DEST/server/src/main/java/org/opensearch/cluster/service/ClusterService.java"
[[ -f "$CS" ]] || exit 0

python3 - "$CS" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
if "public boolean processWriteConditional(" in text:
    print("ClusterService.processWriteConditional already present:", path)
    raise SystemExit(0)
i = text.rfind("\n}")
if i == -1:
    sys.exit(1)
stub = """

    public boolean processWriteConditional(
        org.apache.cassandra.db.ConsistencyLevel cl,
        org.apache.cassandra.db.ConsistencyLevel serialCl,
        final String query,
        Object... values
    ) throws org.apache.cassandra.exceptions.RequestExecutionException,
             org.apache.cassandra.exceptions.RequestValidationException,
             org.apache.cassandra.exceptions.InvalidRequestException {
        return false;
    }
"""
path.write_text(text[:i] + stub + text[i:], encoding="utf-8")
print("Patched ClusterService.processWriteConditional →", path)
PY
