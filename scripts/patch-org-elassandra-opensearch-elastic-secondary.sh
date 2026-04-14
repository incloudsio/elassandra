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
# Keep delayed index builds aligned with the registered Cassandra wrapper index.
perl -i -pe 's/this\.baseCfs\.indexManager\.initIndex\(this\);/this.baseCfs.indexManager.initIndex(registeredIndex);/g' "$F"
python3 - "$F" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

text = text.replace(
    """        if (!isBuilt() &&
            !isBuilding() &&
            mappingInfo != null &&
            mappingInfo.hasAllShardStarted() &&
            needBuild.compareAndSet(true, false))
""",
    """        if (!isBuilt() &&
            !isBuilding() &&
            !baseCfs.isEmpty() &&
            mappingInfo != null &&
            mappingInfo.hasAllShardStarted() &&
            !hasIndexedDocuments(mappingInfo) &&
            needBuild.compareAndSet(true, false))
"""
)

text = text.replace(
    """        return isBuilt() || isBuilding() || baseCfs.isEmpty() ? null : getBuildIndexTask();
""",
    """        return isBuilt() || baseCfs.isEmpty() ? null : getBuildIndexTask();
"""
)

build_old = """        return () -> {\n            this.baseCfs.indexManager.initIndex(registeredIndex);\n            return null;\n        };\n"""
build_current = """        return () -> {\n            this.baseCfs.indexManager.initIndex(registeredIndex);\n            flushBuiltIndices();\n            return null;\n        };\n"""
build_new = """        return () -> {\n            try (ColumnFamilyStore.RefViewFragment viewFragment = this.baseCfs.selectAndReference(View.selectFunction(SSTableSet.CANONICAL))) {\n                registeredIndex.getBuildTaskSupport()\n                        .getIndexBuildTask(1, this.baseCfs, Collections.singleton(registeredIndex), viewFragment.sstables)\n                        .build();\n            }\n            flushBuiltIndices();\n            return null;\n        };\n"""
if build_old in text:
    text = text.replace(build_old, build_new, 1)
if build_current in text:
    text = text.replace(build_current, build_new, 1)

text = text.replace(
    """            baseCfs.indexManager.initIndex(registeredIndex);\n            flushBuiltIndices();\n""",
    """            baseCfs.indexManager.initIndex(registeredIndex);\n"""
)

rebuild_old = """        {\n            logger.info(\"start building secondary {}.{}.{}\", baseCfs.keyspace.getName(), baseCfs.metadata.get().name, indexMetadata.name);\n            baseCfs.indexManager.initIndex(registeredIndex);\n        }\n    }\n\n    private boolean isBuilt() {\n"""
rebuild_new = """        {\n            logger.info(\"start building secondary {}.{}.{}\", baseCfs.keyspace.getName(), baseCfs.metadata.get().name, indexMetadata.name);\n            baseCfs.indexManager.initIndex(registeredIndex);\n        }\n    }\n\n    private boolean hasIndexedDocuments(ImmutableMappingInfo mappingInfo) {\n        if (mappingInfo == null || mappingInfo.indices == null) {\n            return false;\n        }\n        for (ImmutableMappingInfo.ImmutableIndexInfo indexInfo : mappingInfo.indices) {\n            IndexShard indexShard = indexInfo.indexService.getShardOrNull(0);\n            if (indexShard != null && indexShard.state() == IndexShardState.STARTED && indexShard.docStats().getCount() > 0L) {\n                return true;\n            }\n        }\n        return false;\n    }\n\n    private void flushBuiltIndices() {\n        try {\n            ImmutableMappingInfo mappingInfo = mappingInfoRef.get();\n            if (mappingInfo == null || mappingInfo.indices == null) {\n                return;\n            }\n            for (ImmutableMappingInfo.ImmutableIndexInfo indexInfo : mappingInfo.indices) {\n                IndexShard indexShard = indexInfo.indexService.getShardOrNull(0);\n                if (indexShard != null && indexShard.state() == IndexShardState.STARTED) {\n                    indexShard.refresh(\"secondary_index_build\");\n                }\n            }\n        } catch (Exception e) {\n            logger.warn(\"failed to refresh rebuilt secondary index {}\", indexMetadata.name, e);\n        }\n    }\n\n    private boolean isBuilt() {\n"""
if rebuild_old in text and "private void flushBuiltIndices()" not in text:
    text = text.replace(rebuild_old, rebuild_new, 1)

if "private boolean hasIndexedDocuments(ImmutableMappingInfo mappingInfo)" not in text:
    text = text.replace(
        """    private void flushBuiltIndices() {\n""",
        """    private boolean hasIndexedDocuments(ImmutableMappingInfo mappingInfo) {\n        if (mappingInfo == null || mappingInfo.indices == null) {\n            return false;\n        }\n        for (ImmutableMappingInfo.ImmutableIndexInfo indexInfo : mappingInfo.indices) {\n            IndexShard indexShard = indexInfo.indexService.getShardOrNull(0);\n            if (indexShard != null && indexShard.state() == IndexShardState.STARTED && indexShard.docStats().getCount() > 0L) {\n                return true;\n            }\n        }\n        return false;\n    }\n\n    private void flushBuiltIndices() {\n""",
        1
    )

text = text.replace(
    """    private void flushBuiltIndices() {\n        try {\n            Callable<?> flushTask = getBlockingFlushTask();\n            if (flushTask != null) {\n                flushTask.call();\n            }\n        } catch (Exception e) {\n            logger.warn(\"failed to flush rebuilt secondary index {}\", indexMetadata.name, e);\n        }\n    }\n""",
    """    private void flushBuiltIndices() {\n        try {\n            ImmutableMappingInfo mappingInfo = mappingInfoRef.get();\n            if (mappingInfo == null || mappingInfo.indices == null) {\n                return;\n            }\n            for (ImmutableMappingInfo.ImmutableIndexInfo indexInfo : mappingInfo.indices) {\n                IndexShard indexShard = indexInfo.indexService.getShardOrNull(0);\n                if (indexShard != null && indexShard.state() == IndexShardState.STARTED) {\n                    indexShard.refresh(\"secondary_index_build\");\n                }\n            }\n        } catch (Exception e) {\n            logger.warn(\"failed to refresh rebuilt secondary index {}\", indexMetadata.name, e);\n        }\n    }\n"""
)

path.write_text(text, encoding="utf-8")
PY
