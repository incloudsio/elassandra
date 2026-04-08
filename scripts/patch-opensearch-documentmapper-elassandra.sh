#!/usr/bin/env bash
# DocumentMapper: CqlFragments, column defs, Elassandra metadata accessors (fork parity).
#
# Usage: ./scripts/patch-opensearch-documentmapper-elassandra.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${1:?OpenSearch clone root}"
DM="$DEST/server/src/main/java/org/opensearch/index/mapper/DocumentMapper.java"
FRAG="$ROOT/scripts/templates/opensearch-sidecar/documentmapper-elassandra-methods.jfrag"
[[ -f "$DM" ]] || exit 0
[[ -f "$FRAG" ]] || { echo "Missing fragment $FRAG" >&2; exit 1; }

if grep -q 'public CqlFragments getCqlFragments' "$DM"; then
  echo "DocumentMapper already patched: $DM"
  exit 0
fi

python3 - "$DM" "$FRAG" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
frag_path = Path(sys.argv[2])
text = path.read_text(encoding="utf-8")

if "public CqlFragments getCqlFragments" in text:
    print("DocumentMapper already patched (python):", path)
    raise SystemExit(0)

extra_imports = """import org.apache.cassandra.cql3.ColumnIdentifier;
import org.apache.cassandra.schema.ColumnMetadata;
import org.apache.cassandra.schema.TableMetadata;
import org.elassandra.cluster.SchemaManager;

"""
if "org.elassandra.cluster.SchemaManager" not in text:
    text = text.replace(
        "import java.io.IOException;\n",
        "import java.io.IOException;\n" + extra_imports,
        1,
    )
if "import org.opensearch.index.mapper.Mapper;" not in text:
    text = text.replace(
        "import org.opensearch.index.mapper.MapperService.MergeReason;\n",
        "import org.opensearch.index.mapper.Mapper;\nimport org.opensearch.index.mapper.MapperService.MergeReason;\n",
        1,
    )

if "private CqlFragments cqlFragments" not in text:
    needle = """    private final MetadataFieldMapper[] noopTombstoneMetadataFieldMappers;

    public DocumentMapper(MapperService mapperService, Mapping mapping) {"""
    if needle not in text:
        print("DocumentMapper: field anchor not found", file=sys.stderr)
        sys.exit(1)
    repl = """    private final MetadataFieldMapper[] noopTombstoneMetadataFieldMappers;

    /** Elassandra: CQL WHERE fragments (lazy). */
    private CqlFragments cqlFragments = null;

    private Map<String, ColumnMetadata> columnDefs = null;

    public DocumentMapper(MapperService mapperService, Mapping mapping) {"""
    text = text.replace(needle, repl, 1)

needle2 = """    public RoutingFieldMapper routingFieldMapper() {
        return metadataMapper(RoutingFieldMapper.class);
    }

    public IndexFieldMapper IndexFieldMapper() {
        return metadataMapper(IndexFieldMapper.class);
    }"""
if needle2 not in text:
    print("DocumentMapper: routingFieldMapper anchor not found", file=sys.stderr)
    sys.exit(1)
insert2 = frag_path.read_text(encoding="utf-8")
text = text.replace(needle2, insert2, 1)

if "import java.util.LinkedHashMap;" not in text:
    text = text.replace("import java.util.Arrays;\n", "import java.util.Arrays;\nimport java.util.LinkedHashMap;\n", 1)

path.write_text(text, encoding="utf-8")
print("Patched", path)
PY
