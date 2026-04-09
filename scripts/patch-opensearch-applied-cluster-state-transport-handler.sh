#!/usr/bin/env bash
# OpenSearch 1.3 TransportRequestHandler is messageReceived(req, channel, task) only.
#
# Usage: ./scripts/patch-opensearch-applied-cluster-state-transport-handler.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
F="$DEST/server/src/main/java/org/elassandra/discovery/AppliedClusterStateAction.java"
[[ -f "$F" ]] || exit 0

python3 - "$F" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
if "messageReceived(AppliedClusterStateRequest request, final TransportChannel channel, Task task)" in text:
    print("AppliedClusterStateAction transport handler already OpenSearch-style:", path)
    raise SystemExit(0)
old = """    private class AppliedClusterStateRequestHandler implements TransportRequestHandler<AppliedClusterStateRequest> {
        @Override
        public void messageReceived(AppliedClusterStateRequest request, final TransportChannel channel) throws Exception {
            handleAppliedRequest(request, channel);
        }
    }"""
new = """    private class AppliedClusterStateRequestHandler implements TransportRequestHandler<AppliedClusterStateRequest> {
        @Override
        public void messageReceived(AppliedClusterStateRequest request, final TransportChannel channel, Task task) throws Exception {
            handleAppliedRequest(request, channel);
        }
    }"""
if old not in text:
    print("AppliedClusterStateAction: expected 2-arg handler block not found", path, file=sys.stderr)
    sys.exit(1)
text = text.replace(old, new, 1)
if "import org.opensearch.tasks.Task;" not in text:
    needle = "import org.opensearch.threadpool.ThreadPool;"
    if needle not in text:
        print("AppliedClusterStateAction: cannot insert Task import", path, file=sys.stderr)
        sys.exit(1)
    text = text.replace(needle, "import org.opensearch.tasks.Task;\n" + needle, 1)
path.write_text(text, encoding="utf-8")
print("Patched", path)
PY
