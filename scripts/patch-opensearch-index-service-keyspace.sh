#!/usr/bin/env bash
# IndexService#keyspace() (ES 6.8 Elassandra) for CassandraShardStateListener.
#
# Usage: ./scripts/patch-opensearch-index-service-keyspace.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
IS="$DEST/server/src/main/java/org/opensearch/index/IndexService.java"
[[ -f "$IS" ]] || exit 0

python3 - "$IS" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
if "public String keyspace()" in text:
    print("IndexService.keyspace already present:", path)
    raise SystemExit(0)
needle = "    public MapperService mapperService() {\n        return mapperService;\n    }"
if needle not in text:
    print("patch: IndexService mapperService() anchor not found", file=sys.stderr)
    sys.exit(1)
add = """    public MapperService mapperService() {
        return mapperService;
    }

    /** Elassandra: Cassandra keyspace for this index (ES 6.8 fork). */
    public String keyspace() {
        return mapperService.keyspace();
    }
"""
path.write_text(text.replace(needle, add, 1), encoding="utf-8")
print("Patched IndexService.keyspace →", path)
PY
