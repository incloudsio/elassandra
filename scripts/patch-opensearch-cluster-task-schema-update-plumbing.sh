#!/usr/bin/env bash
# Restore Elassandra's schema-aware cluster-task plumbing in the OpenSearch 1.3 sidecar.
# This reintroduces ClusterStateTaskConfig.SchemaUpdate plus the mutation/event transport fields
# that CassandraDiscovery expects during cluster-state publication.
#
# Usage: ./scripts/patch-opensearch-cluster-task-schema-update-plumbing.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
DEST="${1:?OpenSearch clone root}"

python3 - "$DEST" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])


def patch_file(rel_path: str, transform):
    path = root / rel_path
    if not path.exists():
        print(f"Skipping missing {path}")
        return
    original = path.read_text(encoding="utf-8")
    updated = transform(original, path)
    if updated != original:
        path.write_text(updated, encoding="utf-8")
        print(f"Patched {path}")
    else:
        print(f"Already patched {path}")


def replace_once(text: str, old: str, new: str, *, label: str, path: Path) -> str:
    if new in text:
        return text
    if old not in text:
        raise SystemExit(f"{path}: anchor not found for {label}")
    return text.replace(old, new, 1)


def patch_config(text: str, path: Path) -> str:
    text = replace_once(
        text,
        """    Priority priority();\n\n    /**\n     * Build a cluster state update task configuration with the\n""",
        """    Priority priority();\n\n    enum SchemaUpdate {\n        NO_UPDATE,\n        UPDATE,\n        UPDATE_ASYNCHRONOUS;\n\n        public boolean updated() {\n            return this.ordinal() != 0;\n        }\n    }\n\n    default SchemaUpdate schemaUpdate() {\n        return SchemaUpdate.NO_UPDATE;\n    }\n\n    /**\n     * Build a cluster state update task configuration with the\n""",
        label="SchemaUpdate enum",
        path=path,
    )
    text = replace_once(
        text,
        """    static ClusterStateTaskConfig build(Priority priority, TimeValue timeout) {\n        return new Basic(priority, timeout);\n    }\n\n    class Basic implements ClusterStateTaskConfig {\n""",
        """    static ClusterStateTaskConfig build(Priority priority, TimeValue timeout) {\n        return new Basic(priority, timeout);\n    }\n\n    static ClusterStateTaskConfig build(Priority priority, TimeValue timeout, SchemaUpdate schemaUpdate) {\n        return new Basic(priority, timeout) {\n            @Override\n            public SchemaUpdate schemaUpdate() {\n                return schemaUpdate;\n            }\n        };\n    }\n\n    class Basic implements ClusterStateTaskConfig {\n""",
        label="SchemaUpdate build overload",
        path=path,
    )
    return text


def patch_executor(text: str, path: Path) -> str:
    text = replace_once(
        text,
        """import org.opensearch.common.Nullable;\n\nimport java.util.IdentityHashMap;\nimport java.util.List;\nimport java.util.Map;\n""",
        """import org.apache.cassandra.db.Mutation;\nimport org.apache.cassandra.transport.Event;\nimport org.opensearch.cluster.ClusterStateTaskConfig.SchemaUpdate;\nimport org.opensearch.common.Nullable;\n\nimport java.util.Collection;\nimport java.util.Collections;\nimport java.util.IdentityHashMap;\nimport java.util.List;\nimport java.util.Map;\n""",
        label="executor imports",
        path=path,
    )
    text = replace_once(
        text,
        """    class ClusterTasksResult<T> {\n        @Nullable\n        public final ClusterState resultingState;\n        public final Map<T, TaskResult> executionResults;\n\n        /**\n         * Construct an execution result instance with a correspondence between the tasks and their execution result\n         * @param resultingState the resulting cluster state\n         * @param executionResults the correspondence between tasks and their outcome\n         */\n        ClusterTasksResult(ClusterState resultingState, Map<T, TaskResult> executionResults) {\n            this.resultingState = resultingState;\n            this.executionResults = executionResults;\n        }\n\n        public static <T> Builder<T> builder() {\n            return new Builder<>();\n        }\n\n        public static class Builder<T> {\n            private final Map<T, TaskResult> executionResults = new IdentityHashMap<>();\n\n            public Builder<T> success(T task) {\n                return result(task, TaskResult.success());\n            }\n\n            public Builder<T> successes(Iterable<T> tasks) {\n                for (T task : tasks) {\n                    success(task);\n                }\n                return this;\n            }\n\n            public Builder<T> failure(T task, Exception e) {\n                return result(task, TaskResult.failure(e));\n            }\n\n            public Builder<T> failures(Iterable<T> tasks, Exception e) {\n                for (T task : tasks) {\n                    failure(task, e);\n                }\n                return this;\n            }\n\n            private Builder<T> result(T task, TaskResult executionResult) {\n                TaskResult existing = executionResults.put(task, executionResult);\n                assert existing == null : task + \" already has result \" + existing;\n                return this;\n            }\n\n            public ClusterTasksResult<T> build(ClusterState resultingState) {\n                return new ClusterTasksResult<>(resultingState, executionResults);\n            }\n\n            ClusterTasksResult<T> build(ClusterTasksResult<T> result, ClusterState previousState) {\n                return new ClusterTasksResult<>(result.resultingState == null ? previousState : result.resultingState, executionResults);\n            }\n        }\n    }\n""",
        """    class ClusterTasksResult<T> {\n        @Nullable\n        public final ClusterState resultingState;\n        public final Map<T, TaskResult> executionResults;\n        public final SchemaUpdate schemaUpdate;\n        public final Collection<Mutation> mutations;\n        public final Collection<Event.SchemaChange> events;\n\n        /**\n         * Construct an execution result instance with a correspondence between the tasks and their execution result\n         * @param resultingState the resulting cluster state\n         * @param executionResults the correspondence between tasks and their outcome\n         */\n        ClusterTasksResult(ClusterState resultingState, Map<T, TaskResult> executionResults) {\n            this(resultingState, executionResults, SchemaUpdate.NO_UPDATE);\n        }\n\n        ClusterTasksResult(ClusterState resultingState, Map<T, TaskResult> executionResults, SchemaUpdate schemaUpdate) {\n            this(resultingState, executionResults, schemaUpdate, Collections.emptyList(), Collections.emptyList());\n        }\n\n        ClusterTasksResult(\n            ClusterState resultingState,\n            Map<T, TaskResult> executionResults,\n            SchemaUpdate schemaUpdate,\n            Collection<Mutation> cqlMutations,\n            Collection<Event.SchemaChange> events\n        ) {\n            this.resultingState = resultingState;\n            this.executionResults = executionResults;\n            this.schemaUpdate = schemaUpdate;\n            this.mutations = cqlMutations;\n            this.events = events;\n        }\n\n        public static <T> Builder<T> builder() {\n            return new Builder<>();\n        }\n\n        public static class Builder<T> {\n            private final Map<T, TaskResult> executionResults = new IdentityHashMap<>();\n\n            public Builder<T> success(T task) {\n                return result(task, TaskResult.success());\n            }\n\n            public Builder<T> successes(Iterable<T> tasks) {\n                for (T task : tasks) {\n                    success(task);\n                }\n                return this;\n            }\n\n            public Builder<T> failure(T task, Exception e) {\n                return result(task, TaskResult.failure(e));\n            }\n\n            public Builder<T> failures(Iterable<T> tasks, Exception e) {\n                for (T task : tasks) {\n                    failure(task, e);\n                }\n                return this;\n            }\n\n            private Builder<T> result(T task, TaskResult executionResult) {\n                TaskResult existing = executionResults.put(task, executionResult);\n                assert existing == null : task + \" already has result \" + existing;\n                return this;\n            }\n\n            public ClusterTasksResult<T> build(ClusterState resultingState) {\n                return new ClusterTasksResult<>(resultingState, executionResults);\n            }\n\n            public ClusterTasksResult<T> build(ClusterState resultingState, SchemaUpdate schemaUpdate) {\n                return new ClusterTasksResult<>(resultingState, executionResults, schemaUpdate, Collections.emptyList(), Collections.emptyList());\n            }\n\n            public ClusterTasksResult<T> build(\n                ClusterState resultingState,\n                SchemaUpdate schemaUpdate,\n                Collection<Mutation> cqlMutations,\n                Collection<Event.SchemaChange> events\n            ) {\n                return new ClusterTasksResult<>(resultingState, executionResults, schemaUpdate, cqlMutations, events);\n            }\n\n            ClusterTasksResult<T> build(ClusterTasksResult<T> result, ClusterState previousState) {\n                return new ClusterTasksResult<>(result.resultingState == null ? previousState : result.resultingState, executionResults);\n            }\n\n            ClusterTasksResult<T> build(\n                ClusterTasksResult<T> result,\n                ClusterState previousState,\n                SchemaUpdate schemaUpdate,\n                Collection<Mutation> cqlMutations,\n                Collection<Event.SchemaChange> events\n            ) {\n                return new ClusterTasksResult<>(\n                    result.resultingState == null ? previousState : result.resultingState,\n                    executionResults,\n                    schemaUpdate,\n                    cqlMutations,\n                    events\n                );\n            }\n        }\n    }\n""",
        label="ClusterTasksResult schema fields",
        path=path,
    )
    return text


def patch_state_update_task(text: str, path: Path) -> str:
    text = replace_once(
        text,
        """package org.opensearch.cluster;\n\nimport org.opensearch.common.Nullable;\nimport org.opensearch.common.Priority;\nimport org.opensearch.common.unit.TimeValue;\n\nimport java.util.List;\n""",
        """package org.opensearch.cluster;\n\nimport org.apache.cassandra.db.Mutation;\nimport org.apache.cassandra.transport.Event;\nimport org.opensearch.common.Nullable;\nimport org.opensearch.common.Priority;\nimport org.opensearch.common.unit.TimeValue;\n\nimport java.util.Collection;\nimport java.util.Comparator;\nimport java.util.LinkedList;\nimport java.util.List;\n""",
        label="ClusterStateUpdateTask imports",
        path=path,
    )
    text = replace_once(
        text,
        """    @Override\n    public final ClusterTasksResult<ClusterStateUpdateTask> execute(ClusterState currentState, List<ClusterStateUpdateTask> tasks)\n        throws Exception {\n        ClusterState result = execute(currentState);\n        return ClusterTasksResult.<ClusterStateUpdateTask>builder().successes(tasks).build(result);\n    }\n""",
        """    @Override\n    public final ClusterTasksResult<ClusterStateUpdateTask> execute(ClusterState currentState, List<ClusterStateUpdateTask> tasks)\n        throws Exception {\n        Collection<Mutation> mutations = new LinkedList<>();\n        Collection<Event.SchemaChange> events = new LinkedList<>();\n        ClusterState result = execute(currentState, mutations, events);\n        return ClusterTasksResult.<ClusterStateUpdateTask>builder()\n            .successes(tasks)\n            .build(result, tasks.stream().map(ClusterStateUpdateTask::schemaUpdate).max(Comparator.comparing(Enum::ordinal)).get(), mutations, events);\n    }\n""",
        label="ClusterStateUpdateTask execute",
        path=path,
    )
    text = replace_once(
        text,
        """    public abstract ClusterState execute(ClusterState currentState) throws Exception;\n\n    /**\n     * A callback called when execute fails.\n     */\n""",
        """    public abstract ClusterState execute(ClusterState currentState) throws Exception;\n\n    public ClusterState execute(ClusterState currentState, Collection<Mutation> mutations, Collection<Event.SchemaChange> events)\n        throws Exception {\n        return execute(currentState);\n    }\n\n    /**\n     * A callback called when execute fails.\n     */\n""",
        label="ClusterStateUpdateTask overload",
        path=path,
    )
    return text


def patch_local_update_task(text: str, path: Path) -> str:
    text = replace_once(
        text,
        """package org.opensearch.cluster;\n\nimport org.opensearch.common.Nullable;\nimport org.opensearch.common.Priority;\nimport org.opensearch.common.unit.TimeValue;\n\nimport java.util.List;\n""",
        """package org.opensearch.cluster;\n\nimport org.apache.cassandra.db.Mutation;\nimport org.apache.cassandra.transport.Event;\nimport org.opensearch.common.Nullable;\nimport org.opensearch.common.Priority;\nimport org.opensearch.common.unit.TimeValue;\n\nimport java.util.Collection;\nimport java.util.Comparator;\nimport java.util.LinkedList;\nimport java.util.List;\n""",
        label="LocalClusterUpdateTask imports",
        path=path,
    )
    text = replace_once(
        text,
        """    public abstract ClusterTasksResult<LocalClusterUpdateTask> execute(ClusterState currentState) throws Exception;\n\n    @Override\n    public final ClusterTasksResult<LocalClusterUpdateTask> execute(ClusterState currentState, List<LocalClusterUpdateTask> tasks)\n        throws Exception {\n        assert tasks.size() == 1 && tasks.get(0) == this : \"expected one-element task list containing current object but was \" + tasks;\n        ClusterTasksResult<LocalClusterUpdateTask> result = execute(currentState);\n        return ClusterTasksResult.<LocalClusterUpdateTask>builder().successes(tasks).build(result, currentState);\n    }\n""",
        """    public abstract ClusterTasksResult<LocalClusterUpdateTask> execute(ClusterState currentState) throws Exception;\n\n    public ClusterTasksResult<LocalClusterUpdateTask> execute(\n        ClusterState currentState,\n        Collection<Mutation> mutations,\n        Collection<Event.SchemaChange> events\n    ) throws Exception {\n        return execute(currentState);\n    }\n\n    @Override\n    public final ClusterTasksResult<LocalClusterUpdateTask> execute(ClusterState currentState, List<LocalClusterUpdateTask> tasks)\n        throws Exception {\n        assert tasks.size() == 1 && tasks.get(0) == this : \"expected one-element task list containing current object but was \" + tasks;\n        Collection<Mutation> mutations = new LinkedList<>();\n        Collection<Event.SchemaChange> events = new LinkedList<>();\n        ClusterTasksResult<LocalClusterUpdateTask> result = execute(currentState, mutations, events);\n        ClusterStateTaskConfig.SchemaUpdate schemaUpdate = tasks.stream()\n            .map(LocalClusterUpdateTask::schemaUpdate)\n            .max(Comparator.comparing(Enum::ordinal))\n            .get();\n        return ClusterTasksResult.<LocalClusterUpdateTask>builder().successes(tasks).build(result, currentState, schemaUpdate, mutations, events);\n    }\n""",
        label="LocalClusterUpdateTask execute",
        path=path,
    )
    return text


def patch_update_request(text: str, path: Path) -> str:
    text = replace_once(
        text,
        """package org.opensearch.cluster.ack;\n\nimport org.opensearch.common.unit.TimeValue;\n""",
        """package org.opensearch.cluster.ack;\n\nimport org.opensearch.cluster.ClusterStateTaskConfig.SchemaUpdate;\nimport org.opensearch.common.unit.TimeValue;\n""",
        label="ClusterStateUpdateRequest import",
        path=path,
    )
    text = replace_once(
        text,
        """public abstract class ClusterStateUpdateRequest<T extends ClusterStateUpdateRequest<T>> implements AckedRequest {\n\n    private TimeValue ackTimeout;\n    private TimeValue masterNodeTimeout;\n""",
        """public abstract class ClusterStateUpdateRequest<T extends ClusterStateUpdateRequest<T>> implements AckedRequest {\n\n    private TimeValue ackTimeout;\n    private TimeValue masterNodeTimeout;\n    private SchemaUpdate schemaUpdate = SchemaUpdate.NO_UPDATE;\n""",
        label="ClusterStateUpdateRequest field",
        path=path,
    )
    text = replace_once(
        text,
        """    @SuppressWarnings(\"unchecked\")\n    public T masterNodeTimeout(TimeValue masterNodeTimeout) {\n        this.masterNodeTimeout = masterNodeTimeout;\n        return (T) this;\n    }\n}\n""",
        """    @SuppressWarnings(\"unchecked\")\n    public T masterNodeTimeout(TimeValue masterNodeTimeout) {\n        this.masterNodeTimeout = masterNodeTimeout;\n        return (T) this;\n    }\n\n    public SchemaUpdate schemaUpdate() {\n        return schemaUpdate;\n    }\n\n    @SuppressWarnings(\"unchecked\")\n    public T schemaUpdate(SchemaUpdate schemaUpdate) {\n        this.schemaUpdate = schemaUpdate;\n        return (T) this;\n    }\n}\n""",
        label="ClusterStateUpdateRequest accessors",
        path=path,
    )
    return text


def patch_master_service(text: str, path: Path) -> str:
    text = replace_once(
        text,
        """import org.apache.logging.log4j.LogManager;\nimport org.apache.logging.log4j.Logger;\nimport org.apache.logging.log4j.message.ParameterizedMessage;\nimport org.opensearch.Assertions;\n""",
        """import org.apache.cassandra.db.Mutation;\nimport org.apache.cassandra.transport.Event;\nimport org.apache.logging.log4j.LogManager;\nimport org.apache.logging.log4j.Logger;\nimport org.apache.logging.log4j.message.ParameterizedMessage;\nimport org.opensearch.Assertions;\n""",
        label="MasterService cassandra imports",
        path=path,
    )
    text = replace_once(
        text,
        """import org.opensearch.cluster.ClusterStateTaskConfig;\nimport org.opensearch.cluster.ClusterStateTaskExecutor;\n""",
        """import org.opensearch.cluster.ClusterStateTaskConfig;\nimport org.opensearch.cluster.ClusterStateTaskConfig.SchemaUpdate;\nimport org.opensearch.cluster.ClusterStateTaskExecutor;\n""",
        label="MasterService SchemaUpdate import",
        path=path,
    )
    text = replace_once(
        text,
        """import java.util.Arrays;\nimport java.util.HashMap;\nimport java.util.Collections;\nimport java.util.List;\n""",
        """import java.util.Arrays;\nimport java.util.Collection;\nimport java.util.Collections;\nimport java.util.HashMap;\nimport java.util.List;\n""",
        label="MasterService Collection import",
        path=path,
    )
    text = replace_once(
        text,
        """                ClusterChangedEvent clusterChangedEvent = new ClusterChangedEvent(summary, newClusterState, previousClusterState);\n""",
        """                ClusterChangedEvent clusterChangedEvent = new ClusterChangedEvent(\n                    summary,\n                    newClusterState,\n                    previousClusterState,\n                    taskOutputs.schemaUpdate,\n                    taskOutputs.mutations,\n                    taskOutputs.events,\n                    taskOutputs.taskInputs\n                );\n""",
        label="MasterService clusterChangedEvent",
        path=path,
    )
    text = replace_once(
        text,
        """        return new TaskOutputs(\n            taskInputs,\n            previousClusterState,\n            newClusterState,\n            getNonFailedTasks(taskInputs, clusterTasksResult),\n            clusterTasksResult.executionResults\n        );\n""",
        """        return new TaskOutputs(\n            taskInputs,\n            previousClusterState,\n            newClusterState,\n            getNonFailedTasks(taskInputs, clusterTasksResult),\n            clusterTasksResult.executionResults,\n            clusterTasksResult.schemaUpdate,\n            clusterTasksResult.mutations,\n            clusterTasksResult.events\n        );\n""",
        label="MasterService TaskOutputs constructor call",
        path=path,
    )
    text = replace_once(
        text,
        """        final ClusterState newClusterState;\n        final List<Batcher.UpdateTask> nonFailedTasks;\n        final Map<Object, ClusterStateTaskExecutor.TaskResult> executionResults;\n\n        TaskOutputs(\n            TaskInputs taskInputs,\n            ClusterState previousClusterState,\n            ClusterState newClusterState,\n            List<Batcher.UpdateTask> nonFailedTasks,\n            Map<Object, ClusterStateTaskExecutor.TaskResult> executionResults\n        ) {\n            this.taskInputs = taskInputs;\n            this.previousClusterState = previousClusterState;\n            this.newClusterState = newClusterState;\n            this.nonFailedTasks = nonFailedTasks;\n            this.executionResults = executionResults;\n        }\n""",
        """        final ClusterState newClusterState;\n        final List<Batcher.UpdateTask> nonFailedTasks;\n        final Map<Object, ClusterStateTaskExecutor.TaskResult> executionResults;\n        final SchemaUpdate schemaUpdate;\n        final Collection<Mutation> mutations;\n        final Collection<Event.SchemaChange> events;\n\n        TaskOutputs(\n            TaskInputs taskInputs,\n            ClusterState previousClusterState,\n            ClusterState newClusterState,\n            List<Batcher.UpdateTask> nonFailedTasks,\n            Map<Object, ClusterStateTaskExecutor.TaskResult> executionResults,\n            SchemaUpdate schemaUpdate,\n            Collection<Mutation> mutations,\n            Collection<Event.SchemaChange> events\n        ) {\n            this.taskInputs = taskInputs;\n            this.previousClusterState = previousClusterState;\n            this.newClusterState = newClusterState;\n            this.nonFailedTasks = nonFailedTasks;\n            this.executionResults = executionResults;\n            this.schemaUpdate = schemaUpdate;\n            this.mutations = mutations;\n            this.events = events;\n        }\n""",
        label="MasterService TaskOutputs fields",
        path=path,
    )
    return text


def patch_cluster_applier_service(text: str, path: Path) -> str:
    text = replace_once(
        text,
        """import org.opensearch.cluster.ClusterStateObserver;\nimport org.opensearch.cluster.ClusterStateTaskConfig;\nimport org.opensearch.cluster.LocalNodeMasterListener;\n""",
        """import org.opensearch.cluster.ClusterStateObserver;\nimport org.opensearch.cluster.ClusterStateTaskConfig;\nimport org.opensearch.cluster.ClusterStateTaskConfig.SchemaUpdate;\nimport org.opensearch.cluster.LocalNodeMasterListener;\n""",
        label="ClusterApplierService SchemaUpdate import",
        path=path,
    )
    text = replace_once(
        text,
        """    class UpdateTask extends SourcePrioritizedRunnable implements Function<ClusterState, ClusterState> {\n        final ClusterApplyListener listener;\n        final Function<ClusterState, ClusterState> updateFunction;\n\n        UpdateTask(Priority priority, String source, ClusterApplyListener listener, Function<ClusterState, ClusterState> updateFunction) {\n            super(priority, source);\n            this.listener = listener;\n            this.updateFunction = updateFunction;\n        }\n\n        @Override\n        public ClusterState apply(ClusterState clusterState) {\n            return updateFunction.apply(clusterState);\n        }\n\n        @Override\n        public void run() {\n            runTask(this);\n        }\n    }\n""",
        """    class UpdateTask extends SourcePrioritizedRunnable implements Function<ClusterState, ClusterState> {\n        final ClusterApplyListener listener;\n        final Function<ClusterState, ClusterState> updateFunction;\n        final SchemaUpdate schemaUpdate;\n\n        UpdateTask(\n            Priority priority,\n            String source,\n            ClusterApplyListener listener,\n            Function<ClusterState, ClusterState> updateFunction,\n            SchemaUpdate schemaUpdate\n        ) {\n            super(priority, source);\n            this.listener = listener;\n            this.updateFunction = updateFunction;\n            this.schemaUpdate = schemaUpdate;\n        }\n\n        @Override\n        public ClusterState apply(ClusterState clusterState) {\n            return updateFunction.apply(clusterState);\n        }\n\n        @Override\n        public void run() {\n            runTask(this);\n        }\n\n        public SchemaUpdate schemaUpdate() {\n            return this.schemaUpdate;\n        }\n    }\n""",
        label="ClusterApplierService UpdateTask",
        path=path,
    )
    text = replace_once(
        text,
        """            final UpdateTask updateTask = new UpdateTask(\n                config.priority(),\n                source,\n                new SafeClusterApplyListener(listener, supplier, logger),\n                executor\n            );\n""",
        """            final UpdateTask updateTask = new UpdateTask(\n                config.priority(),\n                source,\n                new SafeClusterApplyListener(listener, supplier, logger),\n                executor,\n                config.schemaUpdate()\n            );\n""",
        label="ClusterApplierService submitStateUpdateTask",
        path=path,
    )
    desired_apply_changes = """    private void applyChanges(UpdateTask task, ClusterState previousClusterState, ClusterState newClusterState, StopWatch stopWatch) {\n        ClusterChangedEvent clusterChangedEvent = new ClusterChangedEvent(task.source, newClusterState, previousClusterState, task.schemaUpdate, null);\n        // new cluster state, notify all listeners\n        final DiscoveryNodes.Delta nodesDelta = clusterChangedEvent.nodesDelta();\n        if (nodesDelta.hasChanges() && logger.isInfoEnabled()) {\n            String summary = nodesDelta.shortSummary();\n            if (summary.length() > 0) {\n                logger.info(\n                    \"{}, term: {}, version: {}, reason: {}\",\n                    summary,\n                    newClusterState.term(),\n                    newClusterState.version(),\n                    task.source\n                );\n            }\n        }\n\n        logger.trace(\"connecting to nodes of cluster state with version {}\", newClusterState.version());\n        try (Releasable ignored = stopWatch.timing(\"connecting to new nodes\")) {\n            connectToNodesAndWait(newClusterState);\n        }\n\n        // nothing to do until we actually recover from the gateway or any other block indicates we need to disable persistency\n        if (clusterChangedEvent.state().blocks().disableStatePersistence() == false && clusterChangedEvent.metadataChanged()) {\n            logger.debug(\"applying settings from cluster state with version {}\", newClusterState.version());\n            final Settings incomingSettings = clusterChangedEvent.state().metadata().settings();\n            try (Releasable ignored = stopWatch.timing(\"applying settings\")) {\n                clusterSettings.applySettings(incomingSettings);\n            }\n        }\n\n        logger.debug(\"apply cluster state with version {}\", newClusterState.version());\n\n        nodeConnectionsService.disconnectFromNodesExcept(newClusterState.nodes());\n        callClusterStateAppliers(clusterChangedEvent, stopWatch, highPriorityStateAppliers);\n\n        clusterChangedEvent = new ClusterChangedEvent(task.source, newClusterState, previousClusterState, task.schemaUpdate, null);\n\n        assert newClusterState.coordinationMetadata()\n            .getLastAcceptedConfiguration()\n            .equals(newClusterState.coordinationMetadata().getLastCommittedConfiguration()) : newClusterState.coordinationMetadata()\n                .getLastAcceptedConfiguration()\n                + \" vs \"\n                + newClusterState.coordinationMetadata().getLastCommittedConfiguration()\n                + \" on \"\n                + newClusterState.nodes().getLocalNode();\n\n        logger.debug(\"set locally applied cluster state to version {}\", newClusterState.version());\n        state.set(newClusterState);\n\n        callClusterStateAppliers(clusterChangedEvent, stopWatch, normalPriorityStateAppliers);\n        callClusterStateListeners(clusterChangedEvent, stopWatch);\n        callClusterStateAppliers(clusterChangedEvent, stopWatch, lowPriorityStateAppliers);\n    }\n"""
    original_apply_changes = """    private void applyChanges(UpdateTask task, ClusterState previousClusterState, ClusterState newClusterState, StopWatch stopWatch) {\n        ClusterChangedEvent clusterChangedEvent = new ClusterChangedEvent(task.source, newClusterState, previousClusterState);\n        // new cluster state, notify all listeners\n        final DiscoveryNodes.Delta nodesDelta = clusterChangedEvent.nodesDelta();\n        if (nodesDelta.hasChanges() && logger.isInfoEnabled()) {\n            String summary = nodesDelta.shortSummary();\n            if (summary.length() > 0) {\n                logger.info(\n                    \"{}, term: {}, version: {}, reason: {}\",\n                    summary,\n                    newClusterState.term(),\n                    newClusterState.version(),\n                    task.source\n                );\n            }\n        }\n\n        logger.trace(\"connecting to nodes of cluster state with version {}\", newClusterState.version());\n        try (Releasable ignored = stopWatch.timing(\"connecting to new nodes\")) {\n            connectToNodesAndWait(newClusterState);\n        }\n\n        // nothing to do until we actually recover from the gateway or any other block indicates we need to disable persistency\n        if (clusterChangedEvent.state().blocks().disableStatePersistence() == false && clusterChangedEvent.metadataChanged()) {\n            logger.debug(\"applying settings from cluster state with version {}\", newClusterState.version());\n            final Settings incomingSettings = clusterChangedEvent.state().metadata().settings();\n            try (Releasable ignored = stopWatch.timing(\"applying settings\")) {\n                clusterSettings.applySettings(incomingSettings);\n            }\n        }\n\n        logger.debug(\"apply cluster state with version {}\", newClusterState.version());\n        callClusterStateAppliers(clusterChangedEvent, stopWatch);\n\n        nodeConnectionsService.disconnectFromNodesExcept(newClusterState.nodes());\n\n        assert newClusterState.coordinationMetadata()\n            .getLastAcceptedConfiguration()\n            .equals(newClusterState.coordinationMetadata().getLastCommittedConfiguration()) : newClusterState.coordinationMetadata()\n                .getLastAcceptedConfiguration()\n                + \" vs \"\n                + newClusterState.coordinationMetadata().getLastCommittedConfiguration()\n                + \" on \"\n                + newClusterState.nodes().getLocalNode();\n\n        logger.debug(\"set locally applied cluster state to version {}\", newClusterState.version());\n        state.set(newClusterState);\n\n        callClusterStateListeners(clusterChangedEvent, stopWatch);\n    }\n"""
    wrapped_apply_changes = """    private void applyChanges(UpdateTask task, ClusterState previousClusterState, ClusterState newClusterState, StopWatch stopWatch) {\n        ClusterChangedEvent clusterChangedEvent = new ClusterChangedEvent(task.source, newClusterState, previousClusterState, task.schemaUpdate, null);\n        // new cluster state, notify all listeners\n        final DiscoveryNodes.Delta nodesDelta = clusterChangedEvent.nodesDelta();\n        if (nodesDelta.hasChanges() && logger.isInfoEnabled()) {\n            String summary = nodesDelta.shortSummary();\n            if (summary.length() > 0) {\n                logger.info(\n                    \"{}, term: {}, version: {}, reason: {}\",\n                    summary,\n                    newClusterState.term(),\n                    newClusterState.version(),\n                    task.source\n                );\n            }\n        }\n\n        logger.trace(\"connecting to nodes of cluster state with version {}\", newClusterState.version());\n        try (Releasable ignored = stopWatch.timing(\"connecting to new nodes\")) {\n            connectToNodesAndWait(newClusterState);\n        }\n\n        // nothing to do until we actually recover from the gateway or any other block indicates we need to disable persistency\n        if (clusterChangedEvent.state().blocks().disableStatePersistence() == false && clusterChangedEvent.metadataChanged()) {\n            logger.debug(\"applying settings from cluster state with version {}\", newClusterState.version());\n            final Settings incomingSettings = clusterChangedEvent.state().metadata().settings();\n            try (Releasable ignored = stopWatch.timing(\"applying settings\")) {\n                clusterSettings.applySettings(incomingSettings);\n            }\n        }\n\n        logger.debug(\"apply cluster state with version {}\", newClusterState.version());\n\n        nodeConnectionsService.disconnectFromNodesExcept(newClusterState.nodes());\n\n        try (Releasable ignored = stopWatch.timing(\"running high priority appliers\")) {\n            callClusterStateAppliers(clusterChangedEvent, stopWatch, highPriorityStateAppliers);\n        }\n\n        clusterChangedEvent = new ClusterChangedEvent(task.source, newClusterState, previousClusterState, task.schemaUpdate, null);\n\n        assert newClusterState.coordinationMetadata()\n            .getLastAcceptedConfiguration()\n            .equals(newClusterState.coordinationMetadata().getLastCommittedConfiguration()) : newClusterState.coordinationMetadata()\n                .getLastAcceptedConfiguration()\n                + \" vs \"\n                + newClusterState.coordinationMetadata().getLastCommittedConfiguration()\n                + \" on \"\n                + newClusterState.nodes().getLocalNode();\n\n        logger.debug(\"set locally applied cluster state to version {}\", newClusterState.version());\n        state.set(newClusterState);\n\n        try (Releasable ignored = stopWatch.timing(\"running normal priority appliers\")) {\n            callClusterStateAppliers(clusterChangedEvent, stopWatch, normalPriorityStateAppliers);\n        }\n\n        callClusterStateListeners(clusterChangedEvent, stopWatch);\n\n        try (Releasable ignored = stopWatch.timing(\"running low priority appliers\")) {\n            callClusterStateAppliers(clusterChangedEvent, stopWatch, lowPriorityStateAppliers);\n        }\n    }\n"""
    if desired_apply_changes not in text:
        if original_apply_changes in text:
            text = text.replace(original_apply_changes, desired_apply_changes, 1)
        elif wrapped_apply_changes in text:
            text = text.replace(wrapped_apply_changes, desired_apply_changes, 1)
        else:
            raise SystemExit(f"{path}: anchor not found for ClusterApplierService applyChanges")
    return text


def patch_transport_put_mapping(text: str, path: Path) -> str:
    text = replace_once(
        text,
        """import org.opensearch.cluster.ClusterState;\nimport org.opensearch.cluster.ack.ClusterStateUpdateResponse;\n""",
        """import org.opensearch.cluster.ClusterState;\nimport org.opensearch.cluster.ClusterStateTaskConfig;\nimport org.opensearch.cluster.ack.ClusterStateUpdateResponse;\n""",
        label="TransportPutMappingAction import",
        path=path,
    )
    text = replace_once(
        text,
        """        PutMappingClusterStateUpdateRequest updateRequest = new PutMappingClusterStateUpdateRequest().ackTimeout(request.timeout())\n            .masterNodeTimeout(request.masterNodeTimeout())\n            .indices(concreteIndices)\n            .type(request.type())\n            .source(request.source());\n""",
        """        PutMappingClusterStateUpdateRequest updateRequest = new PutMappingClusterStateUpdateRequest().ackTimeout(request.timeout())\n            .masterNodeTimeout(request.masterNodeTimeout())\n            .schemaUpdate(ClusterStateTaskConfig.SchemaUpdate.UPDATE)\n            .indices(concreteIndices)\n            .type(request.type())\n            .source(request.source());\n""",
        label="TransportPutMappingAction schemaUpdate",
        path=path,
    )
    return text


patch_file("server/src/main/java/org/opensearch/cluster/ClusterStateTaskConfig.java", patch_config)
patch_file("server/src/main/java/org/opensearch/cluster/ClusterStateTaskExecutor.java", patch_executor)
patch_file("server/src/main/java/org/opensearch/cluster/ClusterStateUpdateTask.java", patch_state_update_task)
patch_file("server/src/main/java/org/opensearch/cluster/LocalClusterUpdateTask.java", patch_local_update_task)
patch_file("server/src/main/java/org/opensearch/cluster/ack/ClusterStateUpdateRequest.java", patch_update_request)
patch_file("server/src/main/java/org/opensearch/cluster/service/MasterService.java", patch_master_service)
patch_file("server/src/main/java/org/opensearch/cluster/service/ClusterApplierService.java", patch_cluster_applier_service)
patch_file(
    "server/src/main/java/org/opensearch/action/admin/indices/mapping/put/TransportPutMappingAction.java",
    patch_transport_put_mapping,
)
PY
