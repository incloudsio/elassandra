#!/usr/bin/env bash
# ClusterService: SETTING_CLUSTER_SEARCH_STRATEGY_CLASS for ClusterSettingsTests.
#
# Usage: ./scripts/patch-opensearch-cluster-service-search-strategy-key.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
CS="$DEST/server/src/main/java/org/opensearch/cluster/service/ClusterService.java"
[[ -f "$CS" ]] || exit 0

if grep -q 'CLUSTER_SEARCH_STRATEGY_CLASS_SETTING' "$CS" 2>/dev/null; then
  echo "ClusterService CLUSTER_SEARCH_STRATEGY_CLASS_SETTING already present: $CS"
  exit 0
fi

python3 - "$CS" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

setting_block = """
    public static final String SETTING_CLUSTER_SEARCH_STRATEGY_CLASS = "cluster.search_strategy_class";

    public static final Setting<String> CLUSTER_SEARCH_STRATEGY_CLASS_SETTING =
        Setting.simpleString(
            SETTING_CLUSTER_SEARCH_STRATEGY_CLASS,
            System.getProperty("es.search_strategy_class", org.elassandra.cluster.routing.PrimaryFirstSearchStrategy.class.getName()),
            Property.NodeScope,
            Property.Dynamic
        );
"""

if "CLUSTER_SEARCH_STRATEGY_CLASS_SETTING" in text:
    print("ClusterService search strategy setting already present:", path)
    raise SystemExit(0)

# Upgrade path: only the string constant was added by an older patch.
legacy = '    public static final String SETTING_CLUSTER_SEARCH_STRATEGY_CLASS = "cluster.search_strategy_class";'
if legacy in text and "CLUSTER_SEARCH_STRATEGY_CLASS_SETTING" not in text:
    text = text.replace(legacy, setting_block.strip() + "\n", 1)
    path.write_text(text, encoding="utf-8")
    print("Upgraded ClusterService search strategy → Setting<?> →", path)
    raise SystemExit(0)

marker = '    public static final String INDEX_ON_COMPACTION = "index_on_compaction";'
if marker not in text:
    print("ClusterService: INDEX_ON_COMPACTION marker not found", file=sys.stderr)
    sys.exit(1)
text = text.replace(marker, marker + setting_block, 1)
path.write_text(text, encoding="utf-8")
print("Patched ClusterService search strategy key + Setting →", path)
PY
