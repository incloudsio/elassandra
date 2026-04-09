#!/usr/bin/env bash
# Add Engine.GetResult.elassandraRowExists() for CQL-backed fetches (QueryManager).
#
# Usage: ./scripts/patch-opensearch-engine-elassandra-getresult-factory.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
ENG="$DEST/server/src/main/java/org/opensearch/index/engine/Engine.java"
[[ -f "$ENG" ]] || exit 0

python3 - "$ENG" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
if "elassandraRowExists" in text:
    print("Engine.GetResult.elassandraRowExists already present:", path)
    raise SystemExit(0)
needle = """        public GetResult(Engine.Searcher searcher, DocIdAndVersion docIdAndVersion, boolean fromTranslog) {
            this(true, docIdAndVersion.version, docIdAndVersion, searcher, fromTranslog);
        }

        public boolean exists() {
"""
insert = """        public GetResult(Engine.Searcher searcher, DocIdAndVersion docIdAndVersion, boolean fromTranslog) {
            this(true, docIdAndVersion.version, docIdAndVersion, searcher, fromTranslog);
        }

        /**
         * Elassandra: synthetic get when a CQL row fetch succeeded without opening a Lucene {@link Engine.Searcher}.
         */
        public static GetResult elassandraRowExists() {
            return new GetResult(true, 1L, null, null, false);
        }

        public boolean exists() {
"""
if needle not in text:
    print("Engine.java: insert anchor not found", path, file=sys.stderr)
    sys.exit(1)
text = text.replace(needle, insert, 1)
path.write_text(text, encoding="utf-8")
print("Patched", path)
PY
