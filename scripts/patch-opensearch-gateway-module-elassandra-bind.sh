#!/usr/bin/env bash
# Elassandra: OpenSearch stock GatewayModule binds vanilla GatewayService. Elassandra requires
# CassandraGatewayService (custom performStateRecovery, ring block) — same as ES fork GatewayModule.
# Idempotent.
#
# Usage: ./scripts/patch-opensearch-gateway-module-elassandra-bind.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
GM="$DEST/server/src/main/java/org/opensearch/gateway/GatewayModule.java"
[[ -f "$GM" ]] || exit 0

if grep -q "bind(GatewayService.class).to(CassandraGatewayService.class)" "$GM" 2>/dev/null; then
  echo "GatewayModule already binds CassandraGatewayService → $GM"
  exit 0
fi

python3 - "$GM" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
if "bind(GatewayService.class).to(CassandraGatewayService.class)" in text:
    print("GatewayModule already patched →", path)
    raise SystemExit(0)
if "import org.elassandra.gateway.CassandraGatewayService;" not in text:
    text = text.replace(
        "import org.opensearch.common.inject.AbstractModule;\n\npublic class GatewayModule",
        "import org.opensearch.common.inject.AbstractModule;\n\nimport org.elassandra.gateway.CassandraGatewayService;\n\npublic class GatewayModule",
        1,
    )
if "bind(GatewayService.class).asEagerSingleton();" not in text:
    print("patch: bind(GatewayService.class).asEagerSingleton() not found", path, file=sys.stderr)
    sys.exit(1)
text = text.replace(
    "        bind(GatewayService.class).asEagerSingleton();",
    "        // Elassandra: ES fork GatewayModule parity\n        bind(GatewayService.class).to(CassandraGatewayService.class).asEagerSingleton();",
    1,
)
path.write_text(text, encoding="utf-8")
print("Patched GatewayModule →", path)
PY
