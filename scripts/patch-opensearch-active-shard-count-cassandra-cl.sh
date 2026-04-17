#!/usr/bin/env bash
# Restore Elassandra ActiveShardCount -> Cassandra CL mapping in the OpenSearch sidecar.
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
FILE="$DEST/server/src/main/java/org/opensearch/action/support/ActiveShardCount.java"
[[ -f "$FILE" ]] || exit 0

python3 - "$FILE" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

new = """    /** Elassandra: map replication policy to Cassandra write CL. */
    public ConsistencyLevel toCassandraConsistencyLevel() {
        switch (value) {
            case ACTIVE_SHARD_COUNT_DEFAULT:
                return ConsistencyLevel.LOCAL_ONE;
            case 1:
                return ConsistencyLevel.ONE;
            case 2:
                return ConsistencyLevel.TWO;
            case 3:
                return ConsistencyLevel.THREE;
            case ALL_ACTIVE_SHARDS:
                return ConsistencyLevel.ALL;
            default:
                return ConsistencyLevel.LOCAL_ONE;
        }
    }
"""

if "public ConsistencyLevel toCassandraConsistencyLevel()" in text and "return ConsistencyLevel.LOCAL_ONE;" in text:
    print(f"ActiveShardCount Cassandra CL mapping already patched: {path}")
    raise SystemExit(0)

old = """    /** Elassandra: map replication policy to Cassandra write CL (side-car stub). */
    public ConsistencyLevel toCassandraConsistencyLevel() {
        return ConsistencyLevel.LOCAL_QUORUM;
    }
"""

if "import org.apache.cassandra.db.ConsistencyLevel;\n" not in text:
    import_anchor = "import java.io.IOException;\n"
    if import_anchor not in text:
        print(f"ActiveShardCount Cassandra CL import anchor missing: {path}", file=sys.stderr)
        sys.exit(1)
    text = text.replace(import_anchor, import_anchor + "\nimport org.apache.cassandra.db.ConsistencyLevel;\n", 1)

if old in text:
    text = text.replace(old, new, 1)
else:
    insert_anchor = "}\n"
    idx = text.rfind(insert_anchor)
    if idx == -1:
        print(f"ActiveShardCount Cassandra CL anchor missing: {path}", file=sys.stderr)
        sys.exit(1)
    text = text[:idx] + "\n" + new + text[idx:]

path.write_text(text, encoding="utf-8")
print(f"Patched ActiveShardCount Cassandra CL mapping: {path}")
PY
