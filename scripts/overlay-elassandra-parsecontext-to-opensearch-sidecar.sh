#!/usr/bin/env bash
# Replace stock OpenSearch ParseContext with Elassandra's ES 6.8 fork (rewritten to org.opensearch),
# preserving docs()/allEntries()/nested Document APIs required by ElasticSecondaryIndex.
#
# Usage: ./scripts/overlay-elassandra-parsecontext-to-opensearch-sidecar.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${1:?OpenSearch clone root}"
SRC="$ROOT/server/src/main/java/org/elasticsearch/index/mapper/ParseContext.java"
if [[ ! -f "$SRC" ]] && [[ -f "$ROOT/server/src/main/java/org/opensearch/index/mapper/ParseContext.java" ]]; then
  SRC="$ROOT/server/src/main/java/org/opensearch/index/mapper/ParseContext.java"
fi
DST="$DEST/server/src/main/java/org/opensearch/index/mapper/ParseContext.java"

if [[ ! -f "$SRC" ]]; then
  echo "Missing Elassandra fork ParseContext: $SRC" >&2
  exit 1
fi

mkdir -p "$(dirname "$DST")"
cp "$SRC" "$DST"
perl -i -pe 's/^package org\.elasticsearch\.index\.mapper;/package org.opensearch.index.mapper;/; s/^package org\.opensearch\.index\.mapper;/package org.opensearch.index.mapper;/' "$DST"
"$SCRIPT_DIR/rewrite-engine-java-for-opensearch.sh" --file "$DST"

# OpenSearch uses LegacyESVersion for ES 6.x index version constants.
perl -i -pe 's/\bVersion\.V_6_5_0\b/LegacyESVersion.V_6_5_0/g' "$DST"
python3 - "$DST" <<'PY'
from pathlib import Path
import re
p = Path(__import__("sys").argv[1])
t = p.read_text(encoding="utf-8")
if "import org.opensearch.LegacyESVersion;" not in t:
    t = t.replace(
        "import org.opensearch.Version;\n",
        "import org.opensearch.LegacyESVersion;\nimport org.opensearch.Version;\n",
        1,
    )
# Drop unused Version import if nothing references org.opensearch.Version
if not re.search(r"\bVersion\.", t):
    t = t.replace("import org.opensearch.Version;\n", "")
p.write_text(t, encoding="utf-8")
PY

# Stock OpenSearch AllFieldMapper has no public enabled() — javadoc @link breaks javac -Xdoclint.
python3 - "$DST" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
t = p.read_text(encoding="utf-8")
old = "{@link org.opensearch.index.mapper.AllFieldMapper#enabled()}"
if old in t:
    t = t.replace(old, "AllFieldMapper enabled state", 1)
    p.write_text(t, encoding="utf-8")
PY

echo "Overlay Elassandra ParseContext → $DST"
