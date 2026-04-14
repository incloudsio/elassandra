#!/usr/bin/env bash
# TransportShardBulkAction: wait for the actual mapping change instead of any cluster-state change.
# This avoids waking bulk retries on unrelated metadata updates that happen before the requested
# put-mapping has been applied locally.
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
FILE="$DEST/server/src/main/java/org/opensearch/action/bulk/TransportShardBulkAction.java"
[[ -f "$FILE" ]] || exit 0

python3 - "$FILE" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

if (
    "mappingUpdateAppliedPredicate(" in text
    and "static void performOnPrimary(" in text
    and "private static boolean executeBulkItemRequest(" in text
    and "waitForMappingUpdate.accept(mappingUpdatePredicate, ActionListener.runAfter" in text
):
    print("TransportShardBulkAction mapping wait predicate already patched:", path)
    raise SystemExit(0)


def replace_once(source: str, old: str, new: str, label: str) -> str:
    if new in source:
        return source
    if old not in source:
        raise SystemExit(f"{path}: anchor not found for {label}")
    return source.replace(old, new, 1)


imports_old = """import java.util.Map;\nimport java.util.concurrent.Executor;\nimport java.util.function.Consumer;\nimport java.util.function.Function;\nimport java.util.function.LongSupplier;\n"""
imports_new = """import java.util.Map;\nimport java.util.Objects;\nimport java.util.concurrent.Executor;\nimport java.util.function.BiConsumer;\nimport java.util.function.Consumer;\nimport java.util.function.Function;\nimport java.util.function.LongSupplier;\nimport java.util.function.Predicate;\n"""

dispatch_old = """        }, mappingUpdateListener -> observer.waitForNextChange(new ClusterStateObserver.Listener() {\n            @Override\n            public void onNewClusterState(ClusterState state) {\n                mappingUpdateListener.onResponse(null);\n            }\n\n            @Override\n            public void onClusterServiceClose() {\n                mappingUpdateListener.onFailure(new NodeClosedException(clusterService.localNode()));\n            }\n\n            @Override\n            public void onTimeout(TimeValue timeout) {\n                mappingUpdateListener.onFailure(new MapperException(\"timed out while waiting for a dynamic mapping update\"));\n            }\n        }), listener, threadPool, executor(primary));\n"""
dispatch_new = """        }, (mappingUpdatePredicate, mappingUpdateListener) -> observer.waitForNextChange(new ClusterStateObserver.Listener() {\n            @Override\n            public void onNewClusterState(ClusterState state) {\n                mappingUpdateListener.onResponse(null);\n            }\n\n            @Override\n            public void onClusterServiceClose() {\n                mappingUpdateListener.onFailure(new NodeClosedException(clusterService.localNode()));\n            }\n\n            @Override\n            public void onTimeout(TimeValue timeout) {\n                mappingUpdateListener.onFailure(new MapperException(\"timed out while waiting for a dynamic mapping update\"));\n            }\n        }, mappingUpdatePredicate), listener, threadPool, executor(primary));\n"""

perform_intro_old = """    public static void performOnPrimary(\n        BulkShardRequest request,\n        IndexShard primary,\n        UpdateHelper updateHelper,\n        LongSupplier nowInMillisSupplier,\n        MappingUpdatePerformer mappingUpdater,\n        Consumer<ActionListener<Void>> waitForMappingUpdate,\n        ActionListener<PrimaryResult<BulkShardRequest, BulkShardResponse>> listener,\n        ThreadPool threadPool,\n        String executorName\n    ) {\n        new ActionRunnable<PrimaryResult<BulkShardRequest, BulkShardResponse>>(listener) {\n"""
perform_intro_partial = """    public static void performOnPrimary(\n        BulkShardRequest request,\n        IndexShard primary,\n        UpdateHelper updateHelper,\n        LongSupplier nowInMillisSupplier,\n        MappingUpdatePerformer mappingUpdater,\n        BiConsumer<Predicate<ClusterState>, ActionListener<Void>> waitForMappingUpdate,\n        ActionListener<PrimaryResult<BulkShardRequest, BulkShardResponse>> listener,\n        ThreadPool threadPool,\n        String executorName\n    ) {\n        new ActionRunnable<PrimaryResult<BulkShardRequest, BulkShardResponse>>(listener) {\n"""
perform_intro_new = """    public static void performOnPrimary(\n        BulkShardRequest request,\n        IndexShard primary,\n        UpdateHelper updateHelper,\n        LongSupplier nowInMillisSupplier,\n        MappingUpdatePerformer mappingUpdater,\n        Consumer<ActionListener<Void>> waitForMappingUpdate,\n        ActionListener<PrimaryResult<BulkShardRequest, BulkShardResponse>> listener,\n        ThreadPool threadPool,\n        String executorName\n    ) {\n        performOnPrimary(\n            request,\n            primary,\n            updateHelper,\n            nowInMillisSupplier,\n            mappingUpdater,\n            (mappingUpdatePredicate, mappingUpdateListener) -> waitForMappingUpdate.accept(mappingUpdateListener),\n            listener,\n            threadPool,\n            executorName\n        );\n    }\n\n    static void performOnPrimary(\n        BulkShardRequest request,\n        IndexShard primary,\n        UpdateHelper updateHelper,\n        LongSupplier nowInMillisSupplier,\n        MappingUpdatePerformer mappingUpdater,\n        BiConsumer<Predicate<ClusterState>, ActionListener<Void>> waitForMappingUpdate,\n        ActionListener<PrimaryResult<BulkShardRequest, BulkShardResponse>> listener,\n        ThreadPool threadPool,\n        String executorName\n    ) {\n        new ActionRunnable<PrimaryResult<BulkShardRequest, BulkShardResponse>>(listener) {\n"""

execute_sig_old = """        MappingUpdatePerformer mappingUpdater,\n        Consumer<ActionListener<Void>> waitForMappingUpdate,\n        ActionListener<Void> itemDoneListener\n"""
execute_sig_new = """        MappingUpdatePerformer mappingUpdater,\n        BiConsumer<Predicate<ClusterState>, ActionListener<Void>> waitForMappingUpdate,\n        ActionListener<Void> itemDoneListener\n"""
execute_intro_old = """    static boolean executeBulkItemRequest(\n        BulkPrimaryExecutionContext context,\n        UpdateHelper updateHelper,\n        LongSupplier nowInMillisSupplier,\n        MappingUpdatePerformer mappingUpdater,\n        Consumer<ActionListener<Void>> waitForMappingUpdate,\n        ActionListener<Void> itemDoneListener\n    ) throws Exception {\n        final DocWriteRequest.OpType opType = context.getCurrent().opType();\n"""
execute_intro_partial = """    static boolean executeBulkItemRequest(\n        BulkPrimaryExecutionContext context,\n        UpdateHelper updateHelper,\n        LongSupplier nowInMillisSupplier,\n        MappingUpdatePerformer mappingUpdater,\n        BiConsumer<Predicate<ClusterState>, ActionListener<Void>> waitForMappingUpdate,\n        ActionListener<Void> itemDoneListener\n    ) throws Exception {\n        final DocWriteRequest.OpType opType = context.getCurrent().opType();\n"""
execute_intro_new = """    static boolean executeBulkItemRequest(\n        BulkPrimaryExecutionContext context,\n        UpdateHelper updateHelper,\n        LongSupplier nowInMillisSupplier,\n        MappingUpdatePerformer mappingUpdater,\n        Consumer<ActionListener<Void>> waitForMappingUpdate,\n        ActionListener<Void> itemDoneListener\n    ) throws Exception {\n        return executeBulkItemRequest(\n            context,\n            updateHelper,\n            nowInMillisSupplier,\n            mappingUpdater,\n            (mappingUpdatePredicate, mappingUpdateListener) -> waitForMappingUpdate.accept(mappingUpdateListener),\n            itemDoneListener\n        );\n    }\n\n    private static boolean executeBulkItemRequest(\n        BulkPrimaryExecutionContext context,\n        UpdateHelper updateHelper,\n        LongSupplier nowInMillisSupplier,\n        MappingUpdatePerformer mappingUpdater,\n        BiConsumer<Predicate<ClusterState>, ActionListener<Void>> waitForMappingUpdate,\n        ActionListener<Void> itemDoneListener\n    ) throws Exception {\n        final DocWriteRequest.OpType opType = context.getCurrent().opType();\n"""

mapping_wait_old = """            mappingUpdater.updateMappings(\n                result.getRequiredMappingUpdate(),\n                primary.shardId(),\n                context.getRequestToExecute().type(),\n                new ActionListener<Void>() {\n                    @Override\n                    public void onResponse(Void v) {\n                        context.markAsRequiringMappingUpdate();\n                        waitForMappingUpdate.accept(ActionListener.runAfter(new ActionListener<Void>() {\n                            @Override\n                            public void onResponse(Void v) {\n                                assert context.requiresWaitingForMappingUpdate();\n                                context.resetForExecutionForRetry();\n                            }\n\n                            @Override\n                            public void onFailure(Exception e) {\n                                context.failOnMappingUpdate(e);\n                            }\n                        }, () -> itemDoneListener.onResponse(null)));\n                    }\n"""
mapping_wait_new = """            final CompressedXContent mappingSourceBeforeUpdate = currentMappingSource(\n                primary.indexSettings().getIndexMetadata(),\n                context.getRequestToExecute().type()\n            );\n            final Predicate<ClusterState> mappingUpdatePredicate = mappingUpdateAppliedPredicate(\n                context,\n                mappingSourceBeforeUpdate\n            );\n            mappingUpdater.updateMappings(\n                result.getRequiredMappingUpdate(),\n                primary.shardId(),\n                context.getRequestToExecute().type(),\n                new ActionListener<Void>() {\n                    @Override\n                    public void onResponse(Void v) {\n                        context.markAsRequiringMappingUpdate();\n                        waitForMappingUpdate.accept(mappingUpdatePredicate, ActionListener.runAfter(new ActionListener<Void>() {\n                            @Override\n                            public void onResponse(Void v) {\n                                assert context.requiresWaitingForMappingUpdate();\n                                context.resetForExecutionForRetry();\n                            }\n\n                            @Override\n                            public void onFailure(Exception e) {\n                                context.failOnMappingUpdate(e);\n                            }\n                        }, () -> itemDoneListener.onResponse(null)));\n                    }\n"""

helper_anchor = """    private static Engine.Result exceptionToResult(Exception e, IndexShard primary, boolean isDelete, long version) {\n"""
helper_block = """    private static Predicate<ClusterState> mappingUpdateAppliedPredicate(\n        BulkPrimaryExecutionContext context,\n        CompressedXContent mappingSourceBeforeUpdate\n    ) {\n        final String concreteIndex = context.getConcreteIndex();\n        final String mappingType = context.getRequestToExecute().type();\n        return state -> {\n            final IndexMetadata indexMetadata = state.metadata().index(concreteIndex);\n            if (indexMetadata == null) {\n                return true;\n            }\n            return Objects.equals(mappingSourceBeforeUpdate, currentMappingSource(indexMetadata, mappingType)) == false;\n        };\n    }\n\n    private static CompressedXContent currentMappingSource(IndexMetadata indexMetadata, String mappingType) {\n        if (indexMetadata == null) {\n            return null;\n        }\n        final MappingMetadata mappingMetadata = indexMetadata.mapping(mappingType);\n        if (mappingMetadata != null) {\n            return mappingMetadata.source();\n        }\n        final MappingMetadata fallbackMapping = indexMetadata.mappingOrDefault();\n        return fallbackMapping == null ? null : fallbackMapping.source();\n    }\n\n""" + helper_anchor

text = replace_once(text, imports_old, imports_new, "imports")
text = replace_once(text, dispatch_old, dispatch_new, "observer waitForNextChange")
if perform_intro_new not in text:
    if perform_intro_old in text:
        text = text.replace(perform_intro_old, perform_intro_new, 1)
    elif perform_intro_partial in text:
        text = text.replace(perform_intro_partial, perform_intro_new, 1)
    else:
        raise SystemExit(f"{path}: anchor not found for performOnPrimary overload")
if execute_intro_new not in text:
    if execute_intro_old in text:
        text = text.replace(execute_intro_old, execute_intro_new, 1)
    elif execute_intro_partial in text:
        text = text.replace(execute_intro_partial, execute_intro_new, 1)
    else:
        raise SystemExit(f"{path}: anchor not found for executeBulkItemRequest overload")
text = replace_once(text, mapping_wait_old, mapping_wait_new, "mapping wait branch")
text = replace_once(text, helper_anchor, helper_block, "mapping helper block")

path.write_text(text, encoding="utf-8")
print("Patched TransportShardBulkAction mapping wait predicate:", path)
PY
