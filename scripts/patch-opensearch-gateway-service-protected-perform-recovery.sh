#!/usr/bin/env bash
# Allow Elassandra CassandraGatewayService to override performStateRecovery (OpenSearch 1.3 made it private).
#
# Usage: ./scripts/patch-opensearch-gateway-service-protected-perform-recovery.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
GS="$DEST/server/src/main/java/org/opensearch/gateway/GatewayService.java"
[[ -f "$GS" ]] || exit 0

python3 - "$GS" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
if "protected void performStateRecovery" in text:
    print("GatewayService performStateRecovery already protected:", path)
    raise SystemExit(0)
if "private void performStateRecovery" not in text:
    print("GatewayService: private performStateRecovery not found", path, file=sys.stderr)
    sys.exit(1)
text = text.replace("private void performStateRecovery", "protected void performStateRecovery", 1)
path.write_text(text, encoding="utf-8")
print("Patched", path)
PY
