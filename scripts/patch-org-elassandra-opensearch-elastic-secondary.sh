#!/usr/bin/env bash
# ElasticSecondaryIndex: OpenSearch has no SchemaUpdate / blockingMappingUpdate (Elasticsearch 6.8 fork API).
# To restore dynamic mapping updates on OpenSearch 1.3, wire this call site to the OS mapping pipeline:
# e.g. MetadataMappingService / PutMappingRequest / IndicesClient.putMapping — see org.opensearch.cluster.metadata.MetadataMappingService.
# Also: UidFieldMapper → IdFieldMapper, Uid.createUidAsBytes → Uid.encodeId, MapperService static → instance, parent field guard.
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
F="$DEST/server/src/main/java/org/elassandra/index/ElasticSecondaryIndex.java"
[[ -f "$F" ]] || exit 0
perl -ni -e 'print unless /^import org\.opensearch\.cluster\.ClusterStateTaskConfig\.SchemaUpdate;/' "$F"
perl -i -pe 's/^\s*clusterService\.blockingMappingUpdate\(indexInfo\.indexService\.index\(\), context\.docMapper\(\)\.type\(\), mappingUpdate, SchemaUpdate\.UPDATE_ASYNCHRONOUS\);/            \/\/ TODO(OpenSearch port): restore dynamic mapping update (blockingMappingUpdate)/' "$F"
# OpenSearch 1.3: _uid removed; _id uses IdFieldMapper / Uid.encodeId(BytesRef).
perl -i -pe 's/\bUidFieldMapper\b/IdFieldMapper/g' "$F"
perl -i -pe 's/Uid\.createUidAsBytes\(uid\.type\(\),\s*uid\.id\(\)\)/Uid.encodeId(uid.id())/g' "$F"
perl -i -pe 's/Uid\.createUidAsBytes\(typeName,\s*id\)/Uid.encodeId(id)/g' "$F"
# MapperService.isMetadataField is instance-only in OpenSearch.
perl -i -pe 's/MapperService\.isMetadataField\(/indexInfo.indexService.mapperService().isMetadataField(/g' "$F"
# MappingMetadata has no hasParentField(); inspect parsed mapping map.
perl -i -pe 's/mappingMetaData\.hasParentField\(\)/mappingMap.containsKey(ParentFieldMapper.NAME)/g' "$F"
perl -i -pe 's/mappingMetadata\.hasParentField\(\)/mappingMap.containsKey(ParentFieldMapper.NAME)/g' "$F"
