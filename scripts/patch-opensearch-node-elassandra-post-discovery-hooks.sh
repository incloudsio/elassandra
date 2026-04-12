#!/usr/bin/env bash
# Elassandra: ES fork Node.start() calls ClusterService#createOrUpdateElasticAdminKeyspace and
# CassandraGatewayService#enableMetaDataPersictency after discovery join — releases NO_CASSANDRA_RING_BLOCK.
# Inserts before HttpServerTransport.start() in start(). Idempotent.
#
# Usage: ./scripts/patch-opensearch-node-elassandra-post-discovery-hooks.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
NODE="$DEST/server/src/main/java/org/opensearch/node/Node.java"
[[ -f "$NODE" ]] || exit 0

if grep -q "Elassandra: post-discovery elastic_admin + ring block" "$NODE" 2>/dev/null; then
  echo "Node.java already has Elassandra post-discovery hooks → $NODE"
  exit 0
fi

python3 - "$NODE" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
needle = (
    "        }\n\n"
    "        injector.getInstance(HttpServerTransport.class).start();\n\n"
    "        if (WRITE_PORTS_FILE_SETTING.get(settings())) {"
)
if needle not in text:
    print("patch: Node.java anchor not found", path, file=sys.stderr)
    sys.exit(1)
insert = (
    "        }\n\n"
    "        // Elassandra: post-discovery elastic_admin + ring block (ES fork Node.start() parity)\n"
    "        clusterService.createOrUpdateElasticAdminKeyspace();\n"
    "        injector.getInstance(org.elassandra.gateway.CassandraGatewayService.class).enableMetaDataPersictency();\n\n"
    "        injector.getInstance(HttpServerTransport.class).start();\n\n"
    "        if (WRITE_PORTS_FILE_SETTING.get(settings())) {"
)
path.write_text(text.replace(needle, insert, 1), encoding="utf-8")
print("Patched Node.java post-discovery hooks →", path)
PY
