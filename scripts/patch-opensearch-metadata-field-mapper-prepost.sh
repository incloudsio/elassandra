#!/usr/bin/env bash
# MetadataFieldMapper preCreate/postCreate (ES 6.8 fork parity for ElasticSecondaryIndex).
#
# Usage: ./scripts/patch-opensearch-metadata-field-mapper-prepost.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
MF="$DEST/server/src/main/java/org/opensearch/index/mapper/MetadataFieldMapper.java"
[[ -f "$MF" ]] || exit 0

python3 - "$MF" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
if "void preCreate(ParseContext context)" in text and "Elassandra" in text:
    print("MetadataFieldMapper pre/post already present:", path)
    raise SystemExit(0)
# Insert after class javadoc opening - after "public abstract class MetadataFieldMapper"
old = (
    "public abstract class MetadataFieldMapper extends ParametrizedFieldMapper {\n\n"
    "    public interface TypeParser extends Mapper.TypeParser {"
)
if old not in text:
    print("patch: MetadataFieldMapper class anchor not found", file=sys.stderr)
    sys.exit(1)
new = (
    "public abstract class MetadataFieldMapper extends ParametrizedFieldMapper {\n\n"
    "    /** Elassandra: invoked before root fields are indexed (ES 6.8 fork). */\n"
    "    public void preCreate(ParseContext context) throws IOException {}\n\n"
    "    /** Elassandra: invoked after root fields are indexed (ES 6.8 fork). */\n"
    "    public void postCreate(ParseContext context) throws IOException {}\n\n"
    "    public interface TypeParser extends Mapper.TypeParser {"
)
text = text.replace(old, new, 1)
path.write_text(text, encoding="utf-8")
print("Patched MetadataFieldMapper pre/post →", path)
PY
