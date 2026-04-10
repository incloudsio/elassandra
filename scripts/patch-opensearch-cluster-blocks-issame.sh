#!/usr/bin/env bash
# ClusterBlocks#isSame (ES 6.8 fork) for ElasticSecondaryIndex#clusterChanged.
#
# Usage: ./scripts/patch-opensearch-cluster-blocks-issame.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
CB="$DEST/server/src/main/java/org/opensearch/cluster/block/ClusterBlocks.java"
[[ -f "$CB" ]] || exit 0

python3 - "$CB" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
if "public boolean isSame(ClusterBlocks that" in text:
    print("ClusterBlocks.isSame already present:", path)
    raise SystemExit(0)
needle = "    public boolean hasIndexBlock(String index, ClusterBlock block) {\n        return indicesBlocks.containsKey(index) && indicesBlocks.get(index).contains(block);\n    }"
if needle not in text:
    print("patch: hasIndexBlock anchor not found", file=sys.stderr)
    sys.exit(1)
add = """    public boolean hasIndexBlock(String index, ClusterBlock block) {
        return indicesBlocks.containsKey(index) && indicesBlocks.get(index).contains(block);
    }

    /** Elassandra: compare block sets for a list of indices (ES 6.8 fork). */
    public boolean isSame(ClusterBlocks that, java.util.List<String> indices) {
        for (ClusterBlock block : global) {
            if (!that.hasGlobalBlock(block)) {
                return false;
            }
        }
        for (ClusterBlock block : that.global) {
            if (!hasGlobalBlock(block)) {
                return false;
            }
        }
        for (String index : indices) {
            if (indicesBlocks.get(index) != null) {
                for (ClusterBlock block : indicesBlocks.get(index)) {
                    if (!that.hasIndexBlock(index, block)) {
                        return false;
                    }
                }
            }
        }
        for (String index : indices) {
            if (that.indices().get(index) != null) {
                for (ClusterBlock block : that.indices().get(index)) {
                    if (!hasIndexBlock(index, block)) {
                        return false;
                    }
                }
            }
        }
        return true;
    }
"""
path.write_text(text.replace(needle, add, 1), encoding="utf-8")
print("Patched ClusterBlocks.isSame →", path)
PY
