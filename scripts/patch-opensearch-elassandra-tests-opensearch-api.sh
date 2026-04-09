#!/usr/bin/env bash
# OpenSearch-only fixes for synced org/elassandra tests (after rewrite-engine):
# - FieldMappingMetaData → FieldMappingMetadata (GetFieldMappingsResponse nested type)
# - SearchHits#getTotalHits() returns TotalHits; use .value for long comparisons
#
# Usage: ./scripts/patch-opensearch-elassandra-tests-opensearch-api.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
DIR="$DEST/server/src/test/java/org/elassandra"
[[ -d "$DIR" ]] || exit 0

while IFS= read -r -d '' f; do
  perl -i -pe '
    s/GetFieldMappingsResponse\.FieldMappingMetaData/GetFieldMappingsResponse.FieldMappingMetadata/g;
    s/\bFieldMappingMetaData\b/FieldMappingMetadata/g;
  ' "$f"
done < <(find "$DIR" -name '*.java' -print0)

python3 - "$DIR" <<'PY'
import re
from pathlib import Path
import sys
root = Path(sys.argv[1])
for path in root.rglob("*.java"):
    text = path.read_text(encoding="utf-8")
    # Avoid double-.value
    def repl(m):
        s = m.group(0)
        if ".getTotalHits().value" in s:
            return s
        return s.replace(".getTotalHits()", ".getTotalHits().value", 1)
    new = re.sub(r"\.getHits\(\)\.getTotalHits\(\)(?!\.value)", repl, text)
    if new != text:
        path.write_text(new, encoding="utf-8")
        print("Patched TotalHits.value in", path)
PY

echo "OpenSearch test API compat OK → $DIR"
