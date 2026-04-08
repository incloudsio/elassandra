#!/usr/bin/env bash
# ElasticSecondaryIndex: OpenSearch has no SchemaUpdate / blockingMappingUpdate (Elassandra fork API).
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
F="$DEST/server/src/main/java/org/elassandra/index/ElasticSecondaryIndex.java"
[[ -f "$F" ]] || exit 0
perl -ni -e 'print unless /^import org\.opensearch\.cluster\.ClusterStateTaskConfig\.SchemaUpdate;/' "$F"
perl -i -pe 's/^\s*clusterService\.blockingMappingUpdate\(indexInfo\.indexService\.index\(\), context\.docMapper\(\)\.type\(\), mappingUpdate, SchemaUpdate\.UPDATE_ASYNCHRONOUS\);/            \/\/ TODO(OpenSearch port): restore dynamic mapping update (blockingMappingUpdate)/' "$F"
