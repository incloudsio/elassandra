#!/usr/bin/env bash
# Restore ClusterService#getQueryManager runtime wiring needed by QueryManager-backed bulk indexing.
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
FILE="$DEST/server/src/main/java/org/opensearch/cluster/service/ClusterService.java"
[[ -f "$FILE" ]] || exit 0

python3 - "$FILE" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

if "public org.elassandra.cluster.QueryManager getQueryManager()" in text:
    print(f"ClusterService QueryManager already patched: {path}")
    raise SystemExit(0)

field_needle = "    private final SchemaManager schemaManager;\n"
field_replacement = "    private final SchemaManager schemaManager;\n    private final QueryManager queryManager;\n"
has_querymanager_field = "private final QueryManager queryManager;" in text
if "private final QueryManager queryManager;" not in text:
    if "import org.elassandra.cluster.QueryManager;" not in text and field_needle in text:
        import_needle = "import org.elassandra.cluster.SchemaManager;\n"
        import_replacement = "import org.elassandra.cluster.QueryManager;\nimport org.elassandra.cluster.SchemaManager;\n"
        if import_needle in text:
            text = text.replace(import_needle, import_replacement, 1)
    if field_needle in text:
        text = text.replace(field_needle, field_replacement, 1)
        has_querymanager_field = True

ctor_needle = "        this.schemaManager = new SchemaManager(settings, this);\n"
ctor_replacement = "        this.schemaManager = new SchemaManager(settings, this);\n        this.queryManager = new QueryManager(settings, this);\n"
if has_querymanager_field and "this.queryManager = new QueryManager(settings, this);" not in text:
    if ctor_needle not in text:
        print(f"ClusterService QueryManager ctor anchor missing: {path}", file=sys.stderr)
        sys.exit(1)
    text = text.replace(ctor_needle, ctor_replacement, 1)

getter_needles = [
    """    public org.elassandra.cluster.SchemaManager getSchemaManager() {
        return schemaManager;
    }
""",
    """    public org.elassandra.cluster.SchemaManager getSchemaManager() {
        return null;
    }
""",
]
if has_querymanager_field:
    getter_replacement = """    public org.elassandra.cluster.SchemaManager getSchemaManager() {
        return schemaManager;
    }

    public org.elassandra.cluster.QueryManager getQueryManager() {
        return queryManager;
    }
"""
else:
    getter_replacement = """    public org.elassandra.cluster.SchemaManager getSchemaManager() {
        return null;
    }

    public org.elassandra.cluster.QueryManager getQueryManager() {
        return new org.elassandra.cluster.QueryManager(settings, this);
    }
"""
if "public org.elassandra.cluster.QueryManager getQueryManager()" not in text:
    for getter_needle in getter_needles:
        if getter_needle in text:
            text = text.replace(getter_needle, getter_replacement, 1)
            break
    else:
        print(f"ClusterService QueryManager getter anchor missing: {path}", file=sys.stderr)
        sys.exit(1)

path.write_text(text, encoding="utf-8")
print(f"Patched ClusterService QueryManager wiring: {path}")
PY
