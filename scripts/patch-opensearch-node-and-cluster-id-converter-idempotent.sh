#!/usr/bin/env bash
# NodeAndClusterIdConverter: embedded sidecar tests restart nodes in the same JVM.
# Keep the first logged node/cluster ids instead of failing later cluster-state listeners.
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
FILE="$DEST/server/src/main/java/org/opensearch/common/logging/NodeAndClusterIdConverter.java"
[[ -f "$FILE" ]] || exit 0

python3 - "$FILE" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

old = """    public static void setNodeIdAndClusterId(String nodeId, String clusterUUID) {
        nodeAndClusterId.set(formatIds(clusterUUID, nodeId));
    }
"""

new = """    public static void setNodeIdAndClusterId(String nodeId, String clusterUUID) {
        final String formatted = formatIds(clusterUUID, nodeId);
        if (nodeAndClusterId.get() != null) {
            return;
        }
        try {
            nodeAndClusterId.set(formatted);
        } catch (SetOnce.AlreadySetException ignored) {
            // Embedded Elassandra tests restart nodes in the same JVM; keep the first values.
        }
    }
"""

if new in text:
    print("NodeAndClusterIdConverter already idempotent:", path)
    raise SystemExit(0)

if old not in text:
    raise SystemExit(f"{path}: anchor not found for setNodeIdAndClusterId")

text = text.replace(old, new, 1)
path.write_text(text, encoding="utf-8")
print("Patched NodeAndClusterIdConverter idempotent set:", path)
PY
