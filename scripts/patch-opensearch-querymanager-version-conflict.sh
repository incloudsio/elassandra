#!/usr/bin/env bash
# OpenSearch 1.3 VersionConflictEngineException: (shardId, id, explanation) — no separate "type" parameter.
#
# Usage: ./scripts/patch-opensearch-querymanager-version-conflict.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
QM="$DEST/server/src/main/java/org/elassandra/cluster/QueryManager.java"
[[ -f "$QM" ]] || exit 0

python3 - "$QM" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
old = "throw new VersionConflictEngineException(indexShard.shardId(), cfName, request.id(), \"PAXOS insert failed, document already exists\");"
new = "throw new VersionConflictEngineException(indexShard.shardId(), request.id(), \"PAXOS insert failed, document already exists\");"
if new in text:
    print("QueryManager VersionConflictEngineException already OS-style:", path)
    raise SystemExit(0)
if old not in text:
    print("QueryManager: expected VersionConflict line not found", path, file=sys.stderr)
    sys.exit(1)
text = text.replace(old, new, 1)
path.write_text(text, encoding="utf-8")
print("Patched", path)
PY
