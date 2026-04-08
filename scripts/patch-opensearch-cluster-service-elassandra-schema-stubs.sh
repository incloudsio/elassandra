#!/usr/bin/env bash
# Elassandra SchemaManager expects ClusterService extension keys + secondary index class constants.
# Run after patch-opensearch-cluster-service-elassandra-stubs.sh.
#
# Usage: ./scripts/patch-opensearch-cluster-service-elassandra-schema-stubs.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
CS="$DEST/server/src/main/java/org/opensearch/cluster/service/ClusterService.java"
[[ -f "$CS" ]] || exit 0

python3 - "$CS" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
if "public String getExtensionKey(" in text and "SETTING_CLUSTER_SECONDARY_INDEX_CLASS" in text:
    print("ClusterService schema stubs already present:", path)
    raise SystemExit(0)

if "USER_DEFINED_METADATA" not in text:
    print("unexpected ClusterService layout", file=sys.stderr)
    raise SystemExit(1)

if "SETTING_CLUSTER_SECONDARY_INDEX_CLASS" not in text:
    text = text.replace(
        """    public static final org.opensearch.common.settings.Setting.AffixSetting<String> USER_DEFINED_METADATA = Setting.prefixKeySetting(
        "cluster.metadata.",
        (key) -> Setting.simpleString(key, Property.Dynamic, Property.NodeScope)
    );

    /**
     * The node's settings.
     */""",
        """    public static final org.opensearch.common.settings.Setting.AffixSetting<String> USER_DEFINED_METADATA = Setting.prefixKeySetting(
        "cluster.metadata.",
        (key) -> Setting.simpleString(key, Property.Dynamic, Property.NodeScope)
    );

    /** Elassandra: secondary index class setting key (fork parity; side-car stub). */
    public static final String SETTING_CLUSTER_SECONDARY_INDEX_CLASS = "cluster.secondary_index_class";

    public static final Class<?> defaultSecondaryIndexClass = org.elassandra.index.ExtendedElasticSecondaryIndex.class;

    /**
     * The node's settings.
     */""",
        1,
    )

if "public String getExtensionKey(" not in text:
    needle = "    // --- Elassandra side-car compile stubs (no runtime behaviour; full port replaces these) ---\n\n    public void setDiscovery"
    if needle not in text:
        print("ClusterService: stub needle not found", file=sys.stderr)
        raise SystemExit(1)
    repl = """    // --- Elassandra side-car compile stubs (no runtime behaviour; full port replaces these) ---

    public String getExtensionKey(org.opensearch.cluster.metadata.IndexMetadata indexMetaData) {
        return indexMetaData.getIndex().getName();
    }

    public void putIndexMetaDataExtension(
        org.opensearch.cluster.metadata.IndexMetadata indexMetaData,
        java.util.Map<String, java.nio.ByteBuffer> extensions
    ) {
    }

    public void setDiscovery"""
    text = text.replace(needle, repl, 1)

path.write_text(text, encoding="utf-8")
print("ClusterService schema stubs OK →", path)
PY
