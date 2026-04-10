#!/usr/bin/env bash
# IndexMetadata: Elassandra index Setting keys referenced by org.elassandra.* tests (virtual index, replication, compaction).
#
# Usage: ./scripts/patch-opensearch-indexmetadata-elassandra-test-keys.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
IM="$DEST/server/src/main/java/org/opensearch/cluster/metadata/IndexMetadata.java"
[[ -f "$IM" ]] || exit 0

if grep -q 'INDEX_SETTING_VIRTUAL_SETTING' "$IM" 2>/dev/null; then
  echo "IndexMetadata test keys already present: $IM"
  exit 0
fi

python3 - "$IM" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
needle = """    public static final String SETTING_VIRTUAL = \"index.virtual\";

    /** Cassandra keyspace for this index. */
"""
if needle not in text:
    print("IndexMetadata: SETTING_VIRTUAL anchor not found", file=sys.stderr)
    sys.exit(1)
insert = """    public static final String SETTING_VIRTUAL_INDEX = \"index.virtual_index\";
    public static final org.opensearch.common.settings.Setting<String> INDEX_SETTING_VIRTUAL_INDEX_SETTING =
        org.opensearch.common.settings.Setting.simpleString(
            SETTING_VIRTUAL_INDEX,
            org.opensearch.common.settings.Setting.Property.Final,
            org.opensearch.common.settings.Setting.Property.IndexScope
        );

    public static final org.opensearch.common.settings.Setting<Boolean> INDEX_SETTING_VIRTUAL_SETTING =
        org.opensearch.common.settings.Setting.boolSetting(
            SETTING_VIRTUAL,
            false,
            org.opensearch.common.settings.Setting.Property.Final,
            org.opensearch.common.settings.Setting.Property.IndexScope
        );

    public static final String SETTING_REPLICATION = \"index.replication\";

    public static final String SETTING_INDEX_ON_COMPACTION =
        INDEX_SETTING_PREFIX + org.opensearch.cluster.service.ClusterService.INDEX_ON_COMPACTION;

"""
text = text.replace(
    needle,
    """    public static final String SETTING_VIRTUAL = \"index.virtual\";

"""
    + insert
    + """    /** Cassandra keyspace for this index. */
""",
    1,
)
path.write_text(text, encoding="utf-8")
print("Patched IndexMetadata Elassandra test keys →", path)
PY
