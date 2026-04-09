#!/usr/bin/env bash
# Add deprecated Engine#delete(DeleteByQuery) to OpenSearch Engine if missing (Elassandra secondary index).
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
ENGINE="$DEST/server/src/main/java/org/opensearch/index/engine/Engine.java"
if [[ ! -f "$ENGINE" ]]; then
  echo "No Engine.java at $ENGINE" >&2
  exit 1
fi
# Reset accidental duplicate patches from repeated script runs
if [[ -d "$DEST/.git" ]]; then
  (cd "$DEST" && git checkout -- server/src/main/java/org/opensearch/index/engine/Engine.java) 2>/dev/null || true
fi
COUNT="$(grep -c 'void delete(org\.opensearch\.index\.engine\.DeleteByQuery delete)' "$ENGINE" 2>/dev/null || true)"
if [[ "${COUNT:-0}" -eq 0 ]]; then
  perl -i -0pe '
    s/(\n    public abstract DeleteResult delete\(Delete delete\) throws IOException;\n)/$1\n    \/** Elassandra: retained for secondary-index truncation paths. *\/\n    \@Deprecated\n    public void delete(org.opensearch.index.engine.DeleteByQuery delete) throws EngineException {\n        \/\/ no-op in stock engine; forked InternalEngine may override\n    }\n/s
  ' "$ENGINE"
  echo "Patched Engine.delete(DeleteByQuery): $ENGINE"
fi
python3 - "$ENGINE" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
t = p.read_text(encoding="utf-8")
block = """    /** Elassandra: retained for secondary-index truncation paths. */
    @Deprecated
    public void delete(org.opensearch.index.engine.DeleteByQuery delete) throws EngineException {
        // no-op in stock engine; forked InternalEngine may override
    }

"""
n = t.count(block)
if n > 1:
    t2 = t.replace(block * n, block, 1)
    p.write_text(t2, encoding="utf-8")
    print("Deduplicated Engine.delete(DeleteByQuery) →", p)
PY
