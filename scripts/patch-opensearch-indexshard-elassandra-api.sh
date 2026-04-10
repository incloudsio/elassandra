#!/usr/bin/env bash
# Elassandra calls IndexShard.index/delete(Engine,...) and getEngine()/indexService() from org.elassandra (ES 6.8 visibility).
#
# Usage: ./scripts/patch-opensearch-indexshard-elassandra-api.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
IS="$DEST/server/src/main/java/org/opensearch/index/shard/IndexShard.java"
[[ -f "$IS" ]] || exit 0

python3 - "$IS" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
if "public Engine getEngine()" in text:
    print("IndexShard Elassandra API already patched:", path)
    raise SystemExit(0)
text = text.replace("\n    Engine getEngine() {\n", "\n    public Engine getEngine() {\n", 1)
text = text.replace("\n    private Engine.IndexResult index(Engine engine, Engine.Index index)",
                    "\n    public Engine.IndexResult index(Engine engine, Engine.Index index)", 1)
text = text.replace("\n    private Engine.DeleteResult delete(Engine engine, Engine.Delete delete)",
                    "\n    public Engine.DeleteResult delete(Engine engine, Engine.Delete delete)", 1)
if "public org.opensearch.index.IndexService indexService()" not in text:
    stub = """

    /** Elassandra: ES 6.8 fork stored IndexService on the shard; side-car returns null until full merge. */
    public org.opensearch.index.IndexService indexService() {
        return null;
    }
"""
    i = text.rfind("\n}")
    if i == -1:
        print("IndexShard: no closing brace", file=sys.stderr)
        sys.exit(1)
    text = text[:i] + stub + text[i:]
path.write_text(text, encoding="utf-8")
print("Patched IndexShard Elassandra API →", path)
PY
