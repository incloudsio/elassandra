#!/usr/bin/env bash
# QueryManager: ensure CQL fetch uses Engine.GetResult.elassandraRowExists() (side-car may still have legacy ctor line).
#
# Usage: ./scripts/patch-opensearch-querymanager-opensearch-api.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
QM="$DEST/server/src/main/java/org/elassandra/cluster/QueryManager.java"
[[ -f "$QM" ]] || exit 0

python3 - "$QM" <<'PY'
from pathlib import Path
import re
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
target = "return Engine.GetResult.elassandraRowExists();"
if target in text:
    print("QueryManager GetResult already elassandraRowExists:", path)
    raise SystemExit(0)
# Legacy Patches / hand-edited side-car lines
patterns = [
    r"return new Engine\.GetResult\(true,\s*1L,\s*new DocIdAndVersion\([^)]+\),\s*null,\s*false\)[^;]*;",
    r"return new Engine\.GetResult\(true,\s*1L,\s*new DocIdAndVersion\([^)]+\),\s*null\)[^;]*;",
]
for pat in patterns:
    n, m = re.subn(pat, target, text, count=1)
    if m:
        path.write_text(n, encoding="utf-8")
        print("Patched GetResult line via regex:", path)
        raise SystemExit(0)
print("QueryManager: no GetResult line to patch", path, file=sys.stderr)
sys.exit(1)
PY
