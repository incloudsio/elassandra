#!/usr/bin/env bash
# RangeFieldMapper: inner Range include flags; RangeFieldType#cqlValue; IndexableField in createField loop.
#
# Usage: ./scripts/patch-opensearch-range-fieldmapper-elassandra-compat.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
RF="$DEST/server/src/main/java/org/opensearch/index/mapper/RangeFieldMapper.java"
[[ -f "$RF" ]] || exit 0
python3 - "$RF" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
t = path.read_text(encoding="utf-8")

if "public boolean isIncludeFrom()" not in t:
    old = """        public Object getTo() {
            return to;
        }
    }

    static class BinaryRangesDocValuesField"""
    new = """        public Object getTo() {
            return to;
        }

        public boolean isIncludeFrom() {
            return includeFrom;
        }

        public boolean isIncludeTo() {
            return includeTo;
        }
    }

    static class BinaryRangesDocValuesField"""
    if old not in t:
        print("RangeFieldMapper: Range inner class anchor not found", file=sys.stderr)
        sys.exit(1)
    t = t.replace(old, new, 1)

if "Elassandra RangeFieldType cqlValue" not in t:
    needle = """        public RangeType rangeType() {
            return rangeType;
        }

        @Override
        public IndexFieldData.Builder fielddataBuilder"""
    repl = """        public RangeType rangeType() {
            return rangeType;
        }

        /** Elassandra CQL serialization (fork parity; side-car stub). */
        public Object cqlValue(Object value) {
            return value;
        }

        @Override
        public IndexFieldData.Builder fielddataBuilder"""
    if needle not in t:
        print("RangeFieldMapper: rangeType anchor not found", file=sys.stderr)
        sys.exit(1)
    t = t.replace(needle, repl, 1)

path.write_text(t, encoding="utf-8")
print("Patched RangeFieldMapper Range accessors + RangeFieldType.cqlValue →", path)
PY

# createFields returns IndexableField in Lucene 9 / OpenSearch 1.3
perl -i -pe 's/for \(org\.apache\.lucene\.document\.Field f : fieldType\(\)\.rangeType\.createFields/for (org.apache.lucene.index.IndexableField f : fieldType().rangeType.createFields/' "$RF"
