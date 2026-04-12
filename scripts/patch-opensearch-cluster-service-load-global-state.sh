#!/usr/bin/env bash
# Add ClusterService.loadGlobalState() for Elassandra Gateway (CQL / bootstrap); idempotent.
#
# Usage: ./scripts/patch-opensearch-cluster-service-load-global-state.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
CS="$DEST/server/src/main/java/org/opensearch/cluster/service/ClusterService.java"
[[ -f "$CS" ]] || exit 0

if grep -q 'Metadata loadGlobalState()' "$CS" 2>/dev/null; then
  echo "ClusterService loadGlobalState already present → $CS"
  exit 0
fi

python3 - "$CS" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
needle = """    public String getElasticAdminKeyspaceName() {
        return "elastic_admin";
    }"""
if needle not in text:
    print("ClusterService: getElasticAdminKeyspaceName anchor missing →", path, file=sys.stderr)
    sys.exit(1)
insert = needle + """

    /**
     * Elassandra: load persisted cluster state (CQL). Side-car returns current metadata with a stable
     * cluster UUID when still {@code _na_}, so gateway recovery completes without Zen quorum.
     */
    public org.opensearch.cluster.metadata.Metadata loadGlobalState() throws java.io.IOException {
        org.opensearch.cluster.metadata.Metadata m = state().metadata();
        if (m != null && "_na_".equals(m.clusterUUID())) {
            return org.opensearch.cluster.metadata.Metadata.builder(m)
                .clusterUUID(localNode().getId())
                .build();
        }
        return m;
    }"""
path.write_text(text.replace(needle, insert, 1), encoding="utf-8")
print("Patched ClusterService loadGlobalState →", path)
PY
