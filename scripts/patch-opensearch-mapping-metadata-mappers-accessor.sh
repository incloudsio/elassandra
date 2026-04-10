#!/usr/bin/env bash
# Mapping#metadataMappers() parity with ES 6.8 (ElasticSecondaryIndex indexing loops).
#
# Usage: ./scripts/patch-opensearch-mapping-metadata-mappers-accessor.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
MP="$DEST/server/src/main/java/org/opensearch/index/mapper/Mapping.java"
[[ -f "$MP" ]] || exit 0

python3 - "$MP" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
if "ES 6.8 metadataMappers() iterator parity" in text:
    print("Mapping.metadataMappers() already present:", path)
    raise SystemExit(0)
# OpenSearch 1.3+ ships metadataMappers() on Mapping; nothing to add.
if "public MetadataFieldMapper[] metadataMappers()" in text:
    print("Mapping.metadataMappers() already in upstream:", path)
    raise SystemExit(0)
needle = (
    "    public RootObjectMapper root() {\n"
    "        return root;\n"
    "    }\n\n"
    "    public void validate(MappingLookup mappers) {"
)
if needle not in text:
    print("patch: Mapping root/validate anchor not found", file=sys.stderr)
    sys.exit(1)
add = (
    "    public RootObjectMapper root() {\n"
    "        return root;\n"
    "    }\n\n"
    "    /** Elassandra: ES 6.8 metadataMappers() iterator parity. */\n"
    "    public MetadataFieldMapper[] metadataMappers() {\n"
    "        return metadataMappers;\n"
    "    }\n\n"
    "    public void validate(MappingLookup mappers) {"
)
text = text.replace(needle, add, 1)
path.write_text(text, encoding="utf-8")
print("Patched Mapping.metadataMappers() →", path)
PY
