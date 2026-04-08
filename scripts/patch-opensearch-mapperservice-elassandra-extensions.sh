#!/usr/bin/env bash
# MapperService: keyspace() + getIndexMetadata() delegating to IndexSettings (Elassandra fork parity).
#
# Usage: ./scripts/patch-opensearch-mapperservice-elassandra-extensions.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
MS="$DEST/server/src/main/java/org/opensearch/index/mapper/MapperService.java"
[[ -f "$MS" ]] || exit 0

if grep -q 'public String keyspace()' "$MS"; then
  echo "MapperService already patched: $MS"
  exit 0
fi

python3 - "$MS" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

if "public String keyspace()" in text:
    print("MapperService already patched (python):", path)
    raise SystemExit(0)

needle2 = """    public boolean isMetadataField(String field) {"""
if needle2 not in text:
    print("MapperService: isMetadataField anchor not found", file=sys.stderr)
    sys.exit(1)
insert2 = """    /** Elassandra: Cassandra keyspace backing this index. */
    public String keyspace() {
        return getIndexMetadata().keyspace();
    }

    /** Fork named this getIndexMetaData; OpenSearch uses getIndexMetadata. */
    public org.opensearch.cluster.metadata.IndexMetadata getIndexMetadata() {
        return indexSettings.getIndexMetadata();
    }

    public boolean isMetadataField(String field) {"""
text = text.replace(needle2, insert2, 1)

path.write_text(text, encoding="utf-8")
print("Patched", path)
PY
