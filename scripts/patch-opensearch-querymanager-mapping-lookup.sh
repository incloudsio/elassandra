#!/usr/bin/env bash
# QueryManager: DocumentMapper#mappers() returns MappingLookup on OpenSearch 1.3 (not DocumentFieldMappers).
#
# Usage: ./scripts/patch-opensearch-querymanager-mapping-lookup.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
QM="$DEST/server/src/main/java/org/elassandra/cluster/QueryManager.java"
[[ -f "$QM" ]] || exit 0

python3 - "$QM" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
if "MappingLookup docFieldMappers" in text:
    print("QueryManager MappingLookup already patched:", path)
    raise SystemExit(0)
text = text.replace(
    "final DocumentFieldMappers docFieldMappers = documentMapper.mappers();",
    "final org.opensearch.index.mapper.MappingLookup docFieldMappers = documentMapper.mappers();",
    1,
)
text = text.replace(
    "final DocumentFieldMappers fieldMappers = docMapper.mappers();",
    "final org.opensearch.index.mapper.MappingLookup fieldMappers = docMapper.mappers();",
    1,
)
path.write_text(text, encoding="utf-8")
print("Patched MappingLookup in", path)
PY
