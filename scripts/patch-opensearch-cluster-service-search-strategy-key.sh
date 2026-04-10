#!/usr/bin/env bash
# ClusterService: SETTING_CLUSTER_SEARCH_STRATEGY_CLASS for ClusterSettingsTests.
#
# Usage: ./scripts/patch-opensearch-cluster-service-search-strategy-key.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
CS="$DEST/server/src/main/java/org/opensearch/cluster/service/ClusterService.java"
[[ -f "$CS" ]] || exit 0

if grep -q 'SETTING_CLUSTER_SEARCH_STRATEGY_CLASS' "$CS" 2>/dev/null; then
  echo "ClusterService search strategy key already present: $CS"
  exit 0
fi

python3 - "$CS" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
marker = '    public static final String INDEX_ON_COMPACTION = "index_on_compaction";'
if marker not in text:
    print("ClusterService: INDEX_ON_COMPACTION marker not found", file=sys.stderr)
    sys.exit(1)
block = """
    public static final String SETTING_CLUSTER_SEARCH_STRATEGY_CLASS = "cluster.search_strategy_class";
"""
text = text.replace(marker, marker + block, 1)
path.write_text(text, encoding="utf-8")
print("Patched ClusterService search strategy key →", path)
PY
