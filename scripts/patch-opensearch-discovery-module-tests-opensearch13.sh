#!/usr/bin/env bash
# DiscoveryModuleTests: ctor gained NetworkService + ClusterService + AllocationService + NodeHealthService (OS 1.3).
#
# Usage: ./scripts/patch-opensearch-discovery-module-tests-opensearch13.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
F="$DEST/server/src/test/java/org/opensearch/discovery/DiscoveryModuleTests.java"
[[ -f "$F" ]] || exit 0

if grep -q 'DiscoveryModuleTests OS 1.3 ctor' "$F" 2>/dev/null; then
  echo "DiscoveryModuleTests ctor already patched → $F"
  exit 0
fi
# OpenSearch 1.3+ tests may already pass ClusterService into DiscoveryModule (fresh clone or prior run).
if grep -q 'mock(ClusterService.class)' "$F" 2>/dev/null; then
  echo "DiscoveryModuleTests already has ClusterService mock → $F"
  exit 0
fi

python3 - "$F" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
old = """    private DiscoveryModule newModule(Settings settings, List<DiscoveryPlugin> plugins) {
        return new DiscoveryModule(
            settings,
            threadPool,
            transportService,
            namedWriteableRegistry,
            null,
            masterService,
            clusterApplier,
            clusterSettings,
            plugins,
            null,
            createTempDir().toAbsolutePath(),
            gatewayMetaState,
            mock(RerouteService.class),
            null
        );
    }"""
new = """    private DiscoveryModule newModule(Settings settings, List<DiscoveryPlugin> plugins) {
        return new DiscoveryModule(
            settings,
            threadPool,
            transportService,
            namedWriteableRegistry,
            null,
            masterService,
            mock(org.opensearch.cluster.service.ClusterService.class),
            clusterApplier,
            clusterSettings,
            plugins,
            null,
            createTempDir().toAbsolutePath(),
            gatewayMetaState,
            mock(RerouteService.class),
            null
        );
    }"""
if old not in text:
    print("DiscoveryModuleTests: expected newModule block not found", file=sys.stderr)
    sys.exit(1)
text = text.replace(old, new, 1)
text = "/* DiscoveryModuleTests OS 1.3 ctor */\n" + text
path.write_text(text, encoding="utf-8")
print("Patched DiscoveryModuleTests →", path)
PY
