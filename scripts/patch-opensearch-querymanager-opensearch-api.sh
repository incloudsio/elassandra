#!/usr/bin/env bash
# QueryManager: Engine.GetResult constructor arity for OpenSearch 1.3 (5-arg + fromTranslog).
#
# Usage: ./scripts/patch-opensearch-querymanager-opensearch-api.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
QM="$DEST/server/src/main/java/org/elassandra/cluster/QueryManager.java"
[[ -f "$QM" ]] || exit 0

python3 - "$QM" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
old = "return new Engine.GetResult(true, 1L, new DocIdAndVersion(0, 1L, 1L, 1L, null, 0), null);"
new = "return new Engine.GetResult(true, 1L, new DocIdAndVersion(0, 1L, 1L, 1L, null, 0), null, false); // Elassandra: OS 1.3 GetResult"
if old not in text:
    if "null, false)" in text and "DocIdAndVersion(0, 1L" in text:
        print("QueryManager GetResult already patched:", path)
        raise SystemExit(0)
    print("QueryManager: GetResult line not found", file=sys.stderr)
    sys.exit(1)
text = text.replace(old, new, 1)
path.write_text(text, encoding="utf-8")
print("Patched", path)
PY
