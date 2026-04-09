#!/usr/bin/env bash
# Wire Elassandra discovery types into OpenSearch DiscoveryModule (replacement for removed DiscoveryPlugin#getDiscoveryTypes).
# Branches: discovery.type: cassandra | mock-cassandra
#
# Usage: ./scripts/patch-opensearch-discovery-module-elassandra.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
DM="$DEST/server/src/main/java/org/opensearch/discovery/DiscoveryModule.java"
[[ -f "$DM" ]] || exit 0

python3 - "$DM" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
if "CassandraDiscoveryPlugin.CASSANDRA" in text:
    print("DiscoveryModule already has Elassandra branches:", path)
    raise SystemExit(0)

imports = """import org.elassandra.discovery.CassandraDiscovery;
import org.elassandra.discovery.CassandraDiscoveryPlugin;
import org.elassandra.discovery.MockCassandraDiscovery;
"""
anchor_import = "import org.opensearch.discovery.zen.ZenDiscovery;"
if anchor_import not in text:
    print("DiscoveryModule: expected anchor import not found", path, file=sys.stderr)
    sys.exit(1)
text = text.replace(anchor_import, imports + anchor_import, 1)

needle = "        } else if (Assertions.ENABLED && ZEN_DISCOVERY_TYPE.equals(discoveryType)) {"
if needle not in text:
    print("DiscoveryModule: expected zen test branch not found", path, file=sys.stderr)
    sys.exit(1)

insert = """        } else if (CassandraDiscoveryPlugin.CASSANDRA.equals(discoveryType)) {
            discovery = new CassandraDiscovery(
                settings,
                transportService,
                masterService,
                clusterService,
                clusterApplier,
                clusterSettings,
                namedWriteableRegistry
            );
        } else if (MockCassandraDiscovery.MOCK_CASSANDRA.equals(discoveryType)) {
            discovery = new MockCassandraDiscovery(
                settings,
                transportService,
                masterService,
                clusterService,
                clusterApplier,
                clusterSettings,
                namedWriteableRegistry
            );
        } else if (Assertions.ENABLED && ZEN_DISCOVERY_TYPE.equals(discoveryType)) {"""

text = text.replace(needle, insert, 1)
path.write_text(text, encoding="utf-8")
print("Patched Elassandra discovery branches →", path)
PY
