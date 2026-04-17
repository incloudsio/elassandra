#!/usr/bin/env bash
# Elassandra IndexMetadata extensions: keyspace/table/CQL helpers (fork parity for side-car compile).
#
# Usage: ./scripts/patch-opensearch-indexmetadata-elassandra-extensions.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
IM="$DEST/server/src/main/java/org/opensearch/cluster/metadata/IndexMetadata.java"
[[ -f "$IM" ]] || exit 0

if grep -q 'public String keyspace()' "$IM" && grep -q 'Elassandra CQL / index settings' "$IM"; then
  echo "IndexMetadata already patched: $IM"
  exit 0
fi

python3 - "$IM" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
needle = """    public Settings getSettings() {
        return settings;
    }

    public ImmutableOpenMap<String, AliasMetadata> getAliases() {"""
if needle not in text:
    print("IndexMetadata.java: getSettings anchor not found", file=sys.stderr)
    sys.exit(1)
insert = """    public Settings getSettings() {
        return settings;
    }

    // --- Elassandra CQL / index settings (fork parity; side-car compile stubs) ---

    private static final java.util.regex.Pattern ELASSANDRA_INDEX_TO_KS = java.util.regex.Pattern.compile("\\\\.|\\\\-");

    public static final String SETTING_KEYSPACE = "index.keyspace";
    public static final String SETTING_TABLE = "index.table";
    public static final String SETTING_TABLE_OPTIONS = "index.table_options";
    public static final String SETTING_INDEX_OPAQUE_STORAGE = "index.opaque_storage";
    public static final String SETTING_VIRTUAL = "index.virtual";
    public static final String SETTING_VIRTUAL_INDEX = "index.virtual_index";
    public static final String SETTING_REPLICATION = "index.replication";

    public static final org.opensearch.common.settings.Setting<java.util.List<String>> INDEX_SETTING_REPLICATION_SETTING =
        org.opensearch.common.settings.Setting.listSetting(
            SETTING_REPLICATION,
            java.util.Collections.emptyList(),
            java.util.function.Function.identity(),
            org.opensearch.common.settings.Setting.Property.Final,
            org.opensearch.common.settings.Setting.Property.IndexScope
        );

    /** Cassandra keyspace for this index. */
    public String keyspace() {
        String ks = settings.get(SETTING_KEYSPACE);
        if (ks != null && ks.isEmpty() == false) {
            return ks;
        }
        return ELASSANDRA_INDEX_TO_KS.matcher(index.getName()).replaceAll("_");
    }

    public String table() {
        return settings.get(SETTING_TABLE, org.opensearch.index.mapper.MapperService.SINGLE_MAPPING_NAME);
    }

    public String tableOptions() {
        return settings.get(SETTING_TABLE_OPTIONS);
    }

    public boolean isOpaqueStorage() {
        return settings.getAsBoolean(SETTING_INDEX_OPAQUE_STORAGE, false);
    }

    public boolean isVirtual() {
        return settings.getAsBoolean(SETTING_VIRTUAL, false);
    }

    public String[] partitionFunction() {
        return null;
    }

    public org.elassandra.index.PartitionFunction partitionFunctionClass() {
        return new org.elassandra.index.MessageFormatPartitionFunction();
    }

    /**
     * Mapping for a legacy type name (Elassandra multi-type / CQL paths).
     */
    @Nullable
    public MappingMetadata mapping(String mappingType) {
        return mappings.get(mappingType);
    }

    public ImmutableOpenMap<String, AliasMetadata> getAliases() {"""
text = text.replace(needle, insert, 1)
path.write_text(text, encoding="utf-8")
print("Patched", path)
PY
