#!/usr/bin/env bash
# Make stock OpenSearch 1.3 mappers satisfy Elassandra SchemaManager compile expectations.
#
# Usage: ./scripts/patch-opensearch-mappers-elassandra-cql-compat.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
python3 - "$DEST" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])

def write_if_changed(path: Path, new: str) -> None:
    old = path.read_text(encoding="utf-8") if path.exists() else None
    if old == new:
        print("unchanged", path)
        return
    path.write_text(new, encoding="utf-8")
    print("patched", path)

M = root / "server/src/main/java/org/opensearch/index/mapper/Mapper.java"
if M.exists():
    t = M.read_text(encoding="utf-8")
    if "Elassandra: whether this mapper" not in t:
        needle = """    protected static boolean hasIndexCreated(Settings settings) {
        return settings.hasValue(IndexMetadata.SETTING_INDEX_VERSION_CREATED.getKey());
    }
}
"""
        repl = """    protected static boolean hasIndexCreated(Settings settings) {
        return settings.hasValue(IndexMetadata.SETTING_INDEX_VERSION_CREATED.getKey());
    }

    /**
     * Elassandra: whether this mapper contributes a mapped field (fork parity).
     */
    public boolean hasField() {
        return true;
    }
}
"""
        if needle not in t:
            print("Mapper.java: anchor not found", file=sys.stderr)
            sys.exit(1)
        t = t.replace(needle, repl, 1)
    write_if_changed(M, t)

OM = root / "server/src/main/java/org/opensearch/index/mapper/ObjectMapper.java"
if OM.exists():
    t = OM.read_text(encoding="utf-8")
    if "implements Cloneable, CqlMapper" not in t:
        t = t.replace(
            "public class ObjectMapper extends Mapper implements Cloneable {",
            "public class ObjectMapper extends Mapper implements Cloneable, CqlMapper {",
            1,
        )
    write_if_changed(OM, t)

FM = root / "server/src/main/java/org/opensearch/index/mapper/FieldMapper.java"
if FM.exists():
    t = FM.read_text(encoding="utf-8")
    if "implements Cloneable, CqlMapper" not in t:
        t = t.replace(
            "public abstract class FieldMapper extends Mapper implements Cloneable {",
            "public abstract class FieldMapper extends Mapper implements Cloneable, CqlMapper {",
            1,
        )
    if "Elassandra CQL column type" not in t:
        needle = """        public List<String> copyToFields() {
            return copyToFields;
        }
    }

}
"""
        repl = """        public List<String> copyToFields() {
            return copyToFields;
        }
    }

    /** Elassandra CQL column type for leaf fields (fork parity; side-car stub). */
    public org.apache.cassandra.cql3.CQL3Type.Raw rawType() {
        return org.apache.cassandra.cql3.CQL3Type.Raw.from(org.apache.cassandra.cql3.CQL3Type.Native.TEXT);
    }

}
"""
        if needle not in t:
            print("FieldMapper.java: tail anchor not found", file=sys.stderr)
            sys.exit(1)
        t = t.replace(needle, repl, 1)
    write_if_changed(FM, t)

RF = root / "server/src/main/java/org/opensearch/index/mapper/RangeFieldMapper.java"
if RF.exists():
    t = RF.read_text(encoding="utf-8")
    if "Elassandra CQL UDT field layout" not in t:
        needle = """        @Override
        public BytesRef binaryValue() {
            try {
                return rangeType.encodeRanges(ranges);
            } catch (IOException e) {
                throw new OpenSearchException("failed to encode ranges", e);
            }
        }
    }
}
"""
        repl = """        @Override
        public BytesRef binaryValue() {
            try {
                return rangeType.encodeRanges(ranges);
            } catch (IOException e) {
                throw new OpenSearchException("failed to encode ranges", e);
            }
        }
    }

    /** Elassandra CQL UDT field layout for range types (fork parity; side-car stub). */
    public java.util.Map<String, org.apache.cassandra.cql3.CQL3Type.Raw> cqlFieldTypes() {
        return java.util.Collections.emptyMap();
    }
}
"""
        if needle not in t:
            print("RangeFieldMapper.java: tail anchor not found", file=sys.stderr)
            sys.exit(1)
        t = t.replace(needle, repl, 1)
    write_if_changed(RF, t)

ML = root / "server/src/main/java/org/opensearch/index/mapper/MappingLookup.java"
if ML.exists():
    t = ML.read_text(encoding="utf-8")
    if "smartNameFieldMapper" not in t:
        needle = """    private static String parentObject(String field) {
        int lastDot = field.lastIndexOf('.');
        if (lastDot == -1) {
            return null;
        }
        return field.substring(0, lastDot);
    }
}
"""
        repl = """    private static String parentObject(String field) {
        int lastDot = field.lastIndexOf('.');
        if (lastDot == -1) {
            return null;
        }
        return field.substring(0, lastDot);
    }

    /**
     * Elassandra compatibility ({@code DocumentFieldMappers#smartNameFieldMapper} from ES 6).
     */
    public FieldMapper smartNameFieldMapper(String name) {
        Mapper m = getMapper(name);
        return m instanceof FieldMapper ? (FieldMapper) m : null;
    }
}
"""
        if needle not in t:
            print("MappingLookup.java: tail anchor not found", file=sys.stderr)
            sys.exit(1)
        t = t.replace(needle, repl, 1)
    write_if_changed(ML, t)
PY

chmod +x /Users/maxsmith/Documents/GitHub/elassandra/scripts/patch-opensearch-mappers-elassandra-cql-compat.sh 2>/dev/null || true

echo "OpenSearch mapper Elassandra CQL compat OK → $DEST"
