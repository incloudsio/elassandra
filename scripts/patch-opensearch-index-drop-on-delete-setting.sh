#!/usr/bin/env bash
# Register Elassandra's index.drop_on_delete_index setting in the OpenSearch side-car.
# This lets tests and delete-index code opt out per index instead of only via JVM defaults.
#
# Usage: ./scripts/patch-opensearch-index-drop-on-delete-setting.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
IM="$DEST/server/src/main/java/org/opensearch/cluster/metadata/IndexMetadata.java"
ISS="$DEST/server/src/main/java/org/opensearch/common/settings/IndexScopedSettings.java"
[[ -f "$IM" && -f "$ISS" ]] || exit 0

python3 - "$IM" "$ISS" <<'PY'
from pathlib import Path
import sys

index_metadata = Path(sys.argv[1])
index_scoped_settings = Path(sys.argv[2])

text = index_metadata.read_text(encoding="utf-8")
if "INDEX_DROP_ON_DELETE_INDEX_SETTING" not in text:
    anchor = '    public static final String SETTING_INDEX_OPAQUE_STORAGE = "index.opaque_storage";\n'
    if anchor not in text:
        print(f"{index_metadata}: opaque storage anchor not found", file=sys.stderr)
        raise SystemExit(1)
    insertion = """    public static final String SETTING_DROP_ON_DELETE_INDEX =
        INDEX_SETTING_PREFIX + org.opensearch.cluster.service.ClusterService.DROP_ON_DELETE_INDEX;
    public static final org.opensearch.common.settings.Setting<Boolean> INDEX_DROP_ON_DELETE_INDEX_SETTING =
        org.opensearch.common.settings.Setting.boolSetting(
            SETTING_DROP_ON_DELETE_INDEX,
            Boolean.getBoolean(org.opensearch.cluster.service.ClusterService.SETTING_SYSTEM_DROP_ON_DELETE_INDEX),
            org.opensearch.common.settings.Setting.Property.Dynamic,
            org.opensearch.common.settings.Setting.Property.IndexScope
        );

"""
    text = text.replace(anchor, anchor + insertion, 1)
    index_metadata.write_text(text, encoding="utf-8")
    print("Patched IndexMetadata drop_on_delete setting →", index_metadata)
else:
    print("IndexMetadata drop_on_delete setting already present:", index_metadata)

text = index_scoped_settings.read_text(encoding="utf-8")
needle = "                IndexMetadata.INDEX_DATA_PATH_SETTING,\n"
addition = "                IndexMetadata.INDEX_DROP_ON_DELETE_INDEX_SETTING,\n"
if addition not in text:
    if needle not in text:
        print(f"{index_scoped_settings}: data path anchor not found", file=sys.stderr)
        raise SystemExit(1)
    text = text.replace(needle, needle + addition, 1)
    index_scoped_settings.write_text(text, encoding="utf-8")
    print("Patched IndexScopedSettings drop_on_delete setting →", index_scoped_settings)
else:
    print("IndexScopedSettings drop_on_delete setting already present:", index_scoped_settings)
PY
