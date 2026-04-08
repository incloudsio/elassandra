#!/usr/bin/env bash
# Elassandra Serializer calls MappedFieldType#cqlValue(Object, AbstractType); add stub on OpenSearch MappedFieldType.
#
# Usage: ./scripts/patch-opensearch-mapped-field-type-elassandra-cqlvalue.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
MF="$DEST/server/src/main/java/org/opensearch/index/mapper/MappedFieldType.java"
[[ -f "$MF" ]] || exit 0
if grep -q "Elassandra: encode value for Cassandra" "$MF"; then
  echo "MappedFieldType cqlValue already patched: $MF"
  exit 0
fi
python3 - "$MF" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
t = path.read_text(encoding="utf-8")
needle = """    public TextSearchInfo getTextSearchInfo() {
        return textSearchInfo;
    }
}
"""
if "Elassandra: encode value for Cassandra" in t:
    raise SystemExit(0)
if needle not in t:
    print("MappedFieldType: tail anchor not found", file=sys.stderr)
    sys.exit(1)
repl = """    public TextSearchInfo getTextSearchInfo() {
        return textSearchInfo;
    }

    /** Elassandra: encode value for Cassandra decomposition (fork parity; side-car stub). */
    public Object cqlValue(Object value, org.apache.cassandra.db.marshal.AbstractType<?> type) {
        return value;
    }
}
"""
path.write_text(t.replace(needle, repl, 1), encoding="utf-8")
print("Patched MappedFieldType.cqlValue →", path)
PY
