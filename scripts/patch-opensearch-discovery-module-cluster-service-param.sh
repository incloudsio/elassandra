#!/usr/bin/env bash
# DiscoveryModule wires CassandraDiscovery with ClusterService; the constructor must declare
# ClusterService and Node must pass it. Idempotent for OpenSearch 1.3+ (ClusterService after NetworkService).
#
# Usage: ./scripts/patch-opensearch-discovery-module-cluster-service-param.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
DM="$DEST/server/src/main/java/org/opensearch/discovery/DiscoveryModule.java"
NODE="$DEST/server/src/main/java/org/opensearch/node/Node.java"
[[ -f "$DM" ]] || exit 0

python3 - "$DM" "$NODE" <<'PY'
from pathlib import Path
import re
import sys

dm_path, node_path = Path(sys.argv[1]), Path(sys.argv[2])
text = dm_path.read_text(encoding="utf-8")

# Bad re-run: two ClusterService parameters (NetworkService, ClusterService, MasterService, ClusterService, ...).
text2 = re.sub(
    r"(\n        ClusterService clusterService,\n        MasterService masterService,\n)"
    r"        ClusterService clusterService,\n",
    r"\1",
    text,
    count=1,
)
if text2 != text:
    dm_path.write_text(text2, encoding="utf-8")
    print("Deduped duplicate ClusterService in DiscoveryModule ctor →", dm_path)
    text = text2

has_after_network = bool(
    re.search(
        r"NetworkService networkService,\s*\n\s*ClusterService clusterService,\s*\n\s*MasterService masterService",
        text,
    )
)
has_legacy_insert = "MasterService masterService,\n        ClusterService clusterService,\n        ClusterApplier clusterApplier" in text

if has_after_network or has_legacy_insert:
    print("DiscoveryModule constructor already has ClusterService:", dm_path)
else:
    if "import org.opensearch.cluster.service.ClusterService;" not in text:
        text = text.replace(
            "import org.opensearch.cluster.service.MasterService;\n",
            "import org.opensearch.cluster.service.MasterService;\nimport org.opensearch.cluster.service.ClusterService;\n",
            1,
        )
    old = (
        "        MasterService masterService,\n"
        "        ClusterApplier clusterApplier,"
    )
    new = (
        "        MasterService masterService,\n"
        "        ClusterService clusterService,\n"
        "        ClusterApplier clusterApplier,"
    )
    if old not in text:
        print("patch: DiscoveryModule ctor anchor not found", file=sys.stderr)
        sys.exit(1)
    dm_path.write_text(text.replace(old, new, 1), encoding="utf-8")
    print("Patched DiscoveryModule constructor →", dm_path)

nt = node_path.read_text(encoding="utf-8")
# Accidental double insert: clusterService both before master and between master/applier.
dup = (
    "                clusterService.getMasterService(),\n"
    "                clusterService,\n"
    "                clusterService.getClusterApplierService(),"
)
fix = (
    "                clusterService.getMasterService(),\n"
    "                clusterService.getClusterApplierService(),"
)
if dup in nt:
    node_path.write_text(nt.replace(dup, fix, 1), encoding="utf-8")
    print("Removed duplicate clusterService in Node DiscoveryModule call →", node_path)
    nt = node_path.read_text(encoding="utf-8")

needle = (
    "                clusterService.getMasterService(),\n"
    "                clusterService.getClusterApplierService(),"
)
repl = (
    "                clusterService.getMasterService(),\n"
    "                clusterService,\n"
    "                clusterService.getClusterApplierService(),"
)
if "networkService,\n                clusterService,\n                clusterService.getMasterService()," in nt:
    print("Node already passes clusterService to DiscoveryModule:", node_path)
elif needle in nt:
    node_path.write_text(nt.replace(needle, repl, 1), encoding="utf-8")
    print("Patched Node DiscoveryModule invocation →", node_path)
else:
    print("patch: Node DiscoveryModule call pattern not found", file=sys.stderr)
    sys.exit(1)
PY
