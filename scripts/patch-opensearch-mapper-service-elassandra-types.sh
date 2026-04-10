#!/usr/bin/env bash
# MapperService#types() and hasMapping() (ES 6.8) for CassandraShardStateListener / QueryManager.
#
# Usage: ./scripts/patch-opensearch-mapper-service-elassandra-types.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
MS="$DEST/server/src/main/java/org/opensearch/index/mapper/MapperService.java"
[[ -f "$MS" ]] || exit 0

python3 - "$MS" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
if "public java.util.Set<String> types()" in text:
    print("MapperService types/hasMapping already present:", path)
    raise SystemExit(0)
needle = """    public DocumentMapper documentMapper(String type) {
        if (mapper != null && type.equals(mapper.type())) {
            return mapper;
        }
        if (DEFAULT_MAPPING.equals(type)) {
            return defaultMapper;
        }
        return null;
    }"""
if needle not in text:
    print("patch: documentMapper(String) anchor not found", file=sys.stderr)
    sys.exit(1)
add = needle + """

    /** Elassandra: ES 6.8 types() parity (single-type indices return one entry). */
    public java.util.Set<String> types() {
        if (mapper == null) {
            return java.util.Collections.emptySet();
        }
        return java.util.Collections.singleton(mapper.type());
    }

    public boolean hasMapping(String type) {
        return documentMapper(type) != null;
    }
"""
path.write_text(text.replace(needle, add, 1), encoding="utf-8")
print("Patched MapperService types/hasMapping →", path)
PY
