#!/usr/bin/env bash
# Register ClusterService.CLUSTER_SEARCH_STRATEGY_CLASS_SETTING in BUILT_IN_CLUSTER_SETTINGS (ClusterSettingsTests setUp).
#
# Depends on: patch-opensearch-cluster-service-search-strategy-key.sh
#
# Usage: ./scripts/patch-opensearch-cluster-settings-search-strategy.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
CL="$DEST/server/src/main/java/org/opensearch/common/settings/ClusterSettings.java"
[[ -f "$CL" ]] || exit 0

if grep -q 'CLUSTER_SEARCH_STRATEGY_CLASS_SETTING' "$CL" 2>/dev/null; then
  echo "ClusterSettings search strategy setting already registered: $CL"
  exit 0
fi

python3 - "$CL" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
needle = """                ClusterService.USER_DEFINED_METADATA,
                MasterService.MASTER_SERVICE_SLOW_TASK_LOGGING_THRESHOLD_SETTING,"""
if needle not in text:
    print("ClusterSettings: USER_DEFINED_METADATA / MasterService anchor not found", file=sys.stderr)
    sys.exit(1)
repl = """                ClusterService.USER_DEFINED_METADATA,
                ClusterService.CLUSTER_SEARCH_STRATEGY_CLASS_SETTING,
                MasterService.MASTER_SERVICE_SLOW_TASK_LOGGING_THRESHOLD_SETTING,"""
path.write_text(text.replace(needle, repl, 1), encoding="utf-8")
print("Registered CLUSTER_SEARCH_STRATEGY_CLASS_SETTING →", path)
PY
