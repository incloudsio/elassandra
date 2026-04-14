#!/usr/bin/env bash
# Add ClusterService index-setting key constants used by org.elassandra.cluster.ElassandraIndexSettings
# (short names + SETTING_SYSTEM_* strings). Compile-only stubs for the OpenSearch side-car.
#
# Usage: ./scripts/patch-opensearch-cluster-service-elassandra-index-settings-keys.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
CS="$DEST/server/src/main/java/org/opensearch/cluster/service/ClusterService.java"
[[ -f "$CS" ]] || exit 0

python3 - "$CS" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

# Normalize the Elassandra index-settings block after SETTING_SYSTEM_SYNCHRONOUS_REFRESH.
marker = '    public static final String SETTING_SYSTEM_SYNCHRONOUS_REFRESH = "es.synchronous_refresh";\n'
tail = '    public static final String SETTING_SYSTEM_TOKEN_RANGES_QUERY_EXPIRE = "es.token_ranges_query_expire_minutes";\n'
if marker not in text or tail not in text:
    print("patch-opensearch-cluster-service-elassandra-index-settings-keys: marker not found", file=sys.stderr)
    raise SystemExit(1)

block = """
    public static final String SYNCHRONOUS_REFRESH = "synchronous_refresh";
    public static final String DROP_ON_DELETE_INDEX = "drop_on_delete_index";
    public static final String SNAPSHOT_WITH_SSTABLE = "snapshot_with_sstable";
    public static final String INCLUDE_HOST_ID = "include_node_id";
    public static final String INDEX_ON_COMPACTION = "index_on_compaction";
    public static final String INDEX_STATIC_COLUMNS = "index_static_columns";
    public static final String INDEX_STATIC_ONLY = "index_static_only";
    public static final String INDEX_STATIC_DOCUMENT = "index_static_document";
    public static final String INDEX_INSERT_ONLY = "index_insert_only";
    public static final String INDEX_OPAQUE_STORAGE = "index_opaque_storage";
    public static final String SETTING_SYSTEM_SNAPSHOT_WITH_SSTABLE = "es.snapshot_with_sstable";
    public static final String SETTING_SYSTEM_DROP_ON_DELETE_INDEX = "es.drop_on_delete_index";
    public static final String SETTING_SYSTEM_INDEX_ON_COMPACTION = "es.index_on_compaction";
    public static final String SETTING_SYSTEM_INDEX_INSERT_ONLY = "es.index_insert_only";
    public static final String SETTING_SYSTEM_INDEX_OPAQUE_STORAGE = "es.index_opaque_storage";
"""

start = text.index(marker) + len(marker)
end = text.index(tail, start)
current = text[start:end]
if current == block:
    print("ClusterService index-settings keys already present:", path)
    raise SystemExit(0)

text = text[:start] + block + text[end:]
path.write_text(text, encoding="utf-8")
print("Normalized ElassandraIndexSettings ClusterService keys:", path)
PY
