#!/usr/bin/env bash
# OpenSearch 1.3.x ships a broken {@link #getId()} split across lines (javac doclint errors).
#
# Usage: ./scripts/patch-opensearch-discoverynode-ephemeral-javadoc.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
DN="$DEST/server/src/main/java/org/opensearch/cluster/node/DiscoveryNode.java"
[[ -f "$DN" ]] || exit 0

python3 - "$DN" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
if "* {@link #getId()} will be read from the data folder" in text:
    print("DiscoveryNode getEphemeralId javadoc already fixed:", path)
    raise SystemExit(0)

old = (
    "     * of a node process. When ever a node is restarted, it's ephemeral id is required to change (while it's {@link #getId()}\n"
    "     * will be read from the data folder and will remain the same across restarts). Since all node attributes and addresses\n"
)
new = (
    "     * of a node process. When ever a node is restarted, it's ephemeral id is required to change (while it's\n"
    "     * {@link #getId()} will be read from the data folder and will remain the same across restarts). Since all node attributes and addresses\n"
)
if old not in text:
    print("DiscoveryNode getEphemeralId javadoc anchor not found (skip):", path)
    raise SystemExit(0)
path.write_text(text.replace(old, new, 1), encoding="utf-8")
print("Patched DiscoveryNode getEphemeralId javadoc →", path)
PY
