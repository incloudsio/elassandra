#!/usr/bin/env bash
# Restore Elassandra's primary index path in TransportShardBulkAction so OpenSearch writes flow through QueryManager.
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
    "clusterService.getQueryManager().insertDocument(primary, request, primary.indexSettings().getIndexMetadata())" in text
    and "if (clusterService == null)" in text
    and "return executeBulkItemRequest(" in text
):
    print(f"TransportShardBulkAction QueryManager path already patched: {path}")
    raise SystemExit(0)

perform_call_needle = """        performOnPrimary(request, primary, updateHelper, threadPool::absoluteTimeInMillis, (update, shardId, type, mappingListener) -> {"""
perform_call_replacement = """        performOnPrimary(request, primary, clusterService, updateHelper, threadPool::absoluteTimeInMillis, (update, shardId, type, mappingListener) -> {"""
if perform_call_needle not in text:
    print(f"TransportShardBulkAction performOnPrimary call anchor missing: {path}", file=sys.stderr)
    sys.exit(1)
text = text.replace(perform_call_needle, perform_call_replacement, 1)

perform_sig_needle = """    public static void performOnPrimary(
        BulkShardRequest request,
        IndexShard primary,
        UpdateHelper updateHelper,
        LongSupplier nowInMillisSupplier,
        MappingUpdatePerformer mappingUpdater,
        Consumer<ActionListener<Void>> waitForMappingUpdate,
        ActionListener<PrimaryResult<BulkShardRequest, BulkShardResponse>> listener,
        ThreadPool threadPool,
        String executorName
    ) {"""
perform_sig_replacement = """    public static void performOnPrimary(
        BulkShardRequest request,
        IndexShard primary,
        UpdateHelper updateHelper,
        LongSupplier nowInMillisSupplier,
        MappingUpdatePerformer mappingUpdater,
        Consumer<ActionListener<Void>> waitForMappingUpdate,
        ActionListener<PrimaryResult<BulkShardRequest, BulkShardResponse>> listener,
        ThreadPool threadPool,
        String executorName
    ) {
        performOnPrimary(
            request,
            primary,
            null,
            updateHelper,
            nowInMillisSupplier,
            mappingUpdater,
            waitForMappingUpdate,
            listener,
            threadPool,
            executorName
        );
    }

    public static void performOnPrimary(
        BulkShardRequest request,
        IndexShard primary,
        ClusterService clusterService,
        UpdateHelper updateHelper,
        LongSupplier nowInMillisSupplier,
        MappingUpdatePerformer mappingUpdater,
        Consumer<ActionListener<Void>> waitForMappingUpdate,
        ActionListener<PrimaryResult<BulkShardRequest, BulkShardResponse>> listener,
        ThreadPool threadPool,
        String executorName
    ) {"""
if perform_sig_needle not in text:
    print(f"TransportShardBulkAction performOnPrimary signature anchor missing: {path}", file=sys.stderr)
    sys.exit(1)
text = text.replace(perform_sig_needle, perform_sig_replacement, 1)

call_needle = """                    if (executeBulkItemRequest(
                        context,
                        updateHelper,"""
call_replacement = """                    if (executeBulkItemRequest(
                        context,
                        clusterService,
                        updateHelper,"""
if call_needle not in text:
    print(f"TransportShardBulkAction callsite anchor missing: {path}", file=sys.stderr)
    sys.exit(1)
text = text.replace(call_needle, call_replacement, 1)

sig_needle = """    static boolean executeBulkItemRequest(
        BulkPrimaryExecutionContext context,
        UpdateHelper updateHelper,"""
sig_replacement = """    static boolean executeBulkItemRequest(
        BulkPrimaryExecutionContext context,
        UpdateHelper updateHelper,
        LongSupplier nowInMillisSupplier,
        MappingUpdatePerformer mappingUpdater,
        Consumer<ActionListener<Void>> waitForMappingUpdate,
        ActionListener<Void> itemDoneListener
    ) throws Exception {
        return executeBulkItemRequest(
            context,
            null,
            updateHelper,
            nowInMillisSupplier,
            mappingUpdater,
            waitForMappingUpdate,
            itemDoneListener
        );
    }

    static boolean executeBulkItemRequest(
        BulkPrimaryExecutionContext context,
        ClusterService clusterService,
        UpdateHelper updateHelper,"""
if sig_needle not in text:
    print(f"TransportShardBulkAction signature anchor missing: {path}", file=sys.stderr)
    sys.exit(1)
text = text.replace(sig_needle, sig_replacement, 1)

body_needle = """        } else {
            final IndexRequest request = context.getRequestToExecute();
            result = primary.applyIndexOperationOnPrimary(
                version,
                request.versionType(),
                new SourceToParse(
                    request.index(),
                    request.type(),
                    request.id(),
                    request.source(),
                    request.getContentType(),
                    request.routing()
                ),
                request.ifSeqNo(),
                request.ifPrimaryTerm(),
                request.getAutoGeneratedTimestamp(),
                request.isRetry()
            );
        }"""
body_replacement = """        } else {
            final IndexRequest request = context.getRequestToExecute();
            if (clusterService == null) {
                result = primary.applyIndexOperationOnPrimary(
                    version,
                    request.versionType(),
                    new SourceToParse(
                        request.index(),
                        request.type(),
                        request.id(),
                        request.source(),
                        request.getContentType(),
                        request.routing()
                    ),
                    request.ifSeqNo(),
                    request.ifPrimaryTerm(),
                    request.getAutoGeneratedTimestamp(),
                    request.isRetry()
                );
            } else {
                result = clusterService.getQueryManager().insertDocument(primary, request, primary.indexSettings().getIndexMetadata());
            }
        }"""
if body_needle not in text:
    print(f"TransportShardBulkAction body anchor missing: {path}", file=sys.stderr)
    sys.exit(1)
text = text.replace(body_needle, body_replacement, 1)

path.write_text(text, encoding="utf-8")
print(f"Patched TransportShardBulkAction QueryManager path: {path}")
PY
