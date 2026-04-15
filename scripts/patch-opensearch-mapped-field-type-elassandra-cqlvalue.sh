#!/usr/bin/env bash
# Elassandra Serializer calls MappedFieldType#cqlValue(Object, AbstractType); add stub on OpenSearch MappedFieldType.
#
# Usage: ./scripts/patch-opensearch-mapped-field-type-elassandra-cqlvalue.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
MF="$DEST/server/src/main/java/org/opensearch/index/mapper/MappedFieldType.java"
[[ -f "$MF" ]] || exit 0
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
t = t.replace(
    """    /** Elassandra: encode value for Cassandra decomposition (fork parity; side-car stub). */
    public Object cqlValue(Object value) {
        return cqlValue(value, null);
    }
""",
    """    /** Elassandra: encode value for Cassandra decomposition (fork parity; side-car shim). */
    public Object cqlValue(Object value) {
        return value;
    }
""",
)
t = t.replace(
    """    /** Elassandra: encode value for Cassandra decomposition (fork parity; side-car shim). */
    public Object cqlValue(Object value, org.apache.cassandra.db.marshal.AbstractType<?> type) {
        if (value == null) {
            return null;
        }
        if (type instanceof org.apache.cassandra.db.marshal.BytesType) {
            if (value instanceof org.opensearch.common.bytes.BytesReference) {
                return java.nio.ByteBuffer.wrap(org.opensearch.common.bytes.BytesReference.toBytes((org.opensearch.common.bytes.BytesReference) value));
            }
            if (value instanceof org.apache.lucene.util.BytesRef) {
                org.apache.lucene.util.BytesRef bytesRef = (org.apache.lucene.util.BytesRef) value;
                return java.nio.ByteBuffer.wrap(bytesRef.bytes, bytesRef.offset, bytesRef.length);
            }
        }
        return cqlValue(value);
    }
""",
    """    /** Elassandra: encode value for Cassandra decomposition (fork parity; side-car shim). */
    public Object cqlValue(Object value, org.apache.cassandra.db.marshal.AbstractType<?> type) {
        if (value == null) {
            return null;
        }
        if (type instanceof org.apache.cassandra.db.marshal.BytesType) {
            if (value instanceof org.opensearch.common.bytes.BytesReference) {
                return java.nio.ByteBuffer.wrap(org.opensearch.common.bytes.BytesReference.toBytes((org.opensearch.common.bytes.BytesReference) value));
            }
            if (value instanceof org.apache.lucene.util.BytesRef) {
                org.apache.lucene.util.BytesRef bytesRef = (org.apache.lucene.util.BytesRef) value;
                return java.nio.ByteBuffer.wrap(bytesRef.bytes, bytesRef.offset, bytesRef.length);
            }
        }
        return value;
    }
""",
)
old_stub = """    /** Elassandra: encode value for Cassandra decomposition (fork parity; side-car stub). */
    public Object cqlValue(Object value, org.apache.cassandra.db.marshal.AbstractType<?> type) {
        return value;
    }
"""
old_pair_stub = """    /** Elassandra: encode value for Cassandra decomposition (fork parity; side-car stub). */
    public Object cqlValue(Object value) {
        return cqlValue(value, null);
    }

    /** Elassandra: encode value for Cassandra decomposition (fork parity; side-car stub). */
    public Object cqlValue(Object value, org.apache.cassandra.db.marshal.AbstractType<?> type) {
        return value;
    }
"""
new_stub = """    /** Elassandra: encode value for Cassandra decomposition (fork parity; side-car shim). */
    public Object cqlValue(Object value) {
        return value;
    }

    /** Elassandra: encode value for Cassandra decomposition (fork parity; side-car shim). */
    public Object cqlValue(Object value, org.apache.cassandra.db.marshal.AbstractType<?> type) {
        if (value == null) {
            return null;
        }
        if (type instanceof org.apache.cassandra.db.marshal.BytesType) {
            if (value instanceof org.opensearch.common.bytes.BytesReference) {
                return java.nio.ByteBuffer.wrap(org.opensearch.common.bytes.BytesReference.toBytes((org.opensearch.common.bytes.BytesReference) value));
            }
            if (value instanceof org.apache.lucene.util.BytesRef) {
                org.apache.lucene.util.BytesRef bytesRef = (org.apache.lucene.util.BytesRef) value;
                return java.nio.ByteBuffer.wrap(bytesRef.bytes, bytesRef.offset, bytesRef.length);
            }
        }
        return value;
    }
"""
if old_pair_stub in t:
    path.write_text(t.replace(old_pair_stub, new_stub, 1), encoding="utf-8")
    print("Updated MappedFieldType.cqlValue shim →", path)
    raise SystemExit(0)
if old_stub in t:
    path.write_text(t.replace(old_stub, new_stub, 1), encoding="utf-8")
    print("Updated MappedFieldType.cqlValue shim →", path)
    raise SystemExit(0)
if "Elassandra: encode value for Cassandra decomposition (fork parity; side-car shim)." in t:
    current_pair = """    /** Elassandra: encode value for Cassandra decomposition (fork parity; side-car shim). */
    public Object cqlValue(Object value) {
        return value;
    }

    /** Elassandra: encode value for Cassandra decomposition (fork parity; side-car shim). */
    public Object cqlValue(Object value, org.apache.cassandra.db.marshal.AbstractType<?> type) {
        if (value == null) {
            return null;
        }
        if (type instanceof org.apache.cassandra.db.marshal.BytesType) {
            if (value instanceof org.opensearch.common.bytes.BytesReference) {
                return java.nio.ByteBuffer.wrap(org.opensearch.common.bytes.BytesReference.toBytes((org.opensearch.common.bytes.BytesReference) value));
            }
            if (value instanceof org.apache.lucene.util.BytesRef) {
                org.apache.lucene.util.BytesRef bytesRef = (org.apache.lucene.util.BytesRef) value;
                return java.nio.ByteBuffer.wrap(bytesRef.bytes, bytesRef.offset, bytesRef.length);
            }
        }
        return cqlValue(value);
    }
"""
    if current_pair in t:
        path.write_text(t.replace(current_pair, new_stub, 1), encoding="utf-8")
        print("Updated MappedFieldType.cqlValue shim →", path)
    else:
        if "public Object cqlValue(Object value) {\n        return value;\n    }" in t and "return value;\n    }\n" in t:
            path.write_text(t, encoding="utf-8")
            print("Updated MappedFieldType.cqlValue shim →", path)
        else:
            print("MappedFieldType cqlValue already patched:", path)
    raise SystemExit(0)
if needle not in t:
    print("MappedFieldType: tail anchor not found", file=sys.stderr)
    sys.exit(1)
repl = """    public TextSearchInfo getTextSearchInfo() {
        return textSearchInfo;
    }

    /** Elassandra: encode value for Cassandra decomposition (fork parity; side-car shim). */
    public Object cqlValue(Object value) {
        return value;
    }

    /** Elassandra: encode value for Cassandra decomposition (fork parity; side-car shim). */
    public Object cqlValue(Object value, org.apache.cassandra.db.marshal.AbstractType<?> type) {
        if (value == null) {
            return null;
        }
        if (type instanceof org.apache.cassandra.db.marshal.BytesType) {
            if (value instanceof org.opensearch.common.bytes.BytesReference) {
                return java.nio.ByteBuffer.wrap(org.opensearch.common.bytes.BytesReference.toBytes((org.opensearch.common.bytes.BytesReference) value));
            }
            if (value instanceof org.apache.lucene.util.BytesRef) {
                org.apache.lucene.util.BytesRef bytesRef = (org.apache.lucene.util.BytesRef) value;
                return java.nio.ByteBuffer.wrap(bytesRef.bytes, bytesRef.offset, bytesRef.length);
            }
        }
        return value;
    }
}
"""
path.write_text(t.replace(needle, repl, 1), encoding="utf-8")
print("Patched MappedFieldType.cqlValue →", path)
PY
