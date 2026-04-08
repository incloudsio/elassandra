#!/usr/bin/env bash
# Elassandra CassandraDiscovery needs TaskInputs.updateTasksToMap(...) and visible fields (Elasticsearch 6.8 fork parity).
#
# Usage: ./scripts/patch-opensearch-master-service-taskinputs-public.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
MS="$DEST/server/src/main/java/org/opensearch/cluster/service/MasterService.java"
if [[ ! -f "$MS" ]]; then
  echo "No MasterService.java at $MS" >&2
  exit 1
fi

if grep -q 'updateTasksToMap' "$MS"; then
  echo "MasterService TaskInputs already extended: $MS"
  exit 0
fi

if ! grep -q 'import java.util.HashMap;' "$MS"; then
  perl -i -pe 's/^import java.util.Arrays;/import java.util.Arrays;\nimport java.util.HashMap;/' "$MS"
fi

python3 - "$MS" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
old = """    private class TaskInputs {
        final String summary;
        final List<Batcher.UpdateTask> updateTasks;
        final ClusterStateTaskExecutor<Object> executor;

        TaskInputs(ClusterStateTaskExecutor<Object> executor, List<Batcher.UpdateTask> updateTasks, String summary) {
            this.summary = summary;
            this.executor = executor;
            this.updateTasks = updateTasks;
        }

        boolean runOnlyWhenMaster() {
            return executor.runOnlyOnMaster();
        }

        void onNoLongerMaster() {
            updateTasks.forEach(task -> task.listener.onNoLongerMaster(task.source()));
        }
    }"""
new = """    public class TaskInputs {
        public final String summary;
        public final List<Batcher.UpdateTask> updateTasks;
        public final ClusterStateTaskExecutor<Object> executor;

        TaskInputs(ClusterStateTaskExecutor<Object> executor, List<Batcher.UpdateTask> updateTasks, String summary) {
            this.summary = summary;
            this.executor = executor;
            this.updateTasks = updateTasks;
        }

        boolean runOnlyWhenMaster() {
            return executor.runOnlyOnMaster();
        }

        void onNoLongerMaster() {
            updateTasks.forEach(task -> task.listener.onNoLongerMaster(task.source()));
        }

        /** Elassandra: rebuild task map when resubmitting after PAXOS conflict (fork parity). */
        public Map<Object, ClusterStateTaskListener> updateTasksToMap(Priority priority, final long lostTimeMillis) {
            Map<Object, ClusterStateTaskListener> map = new HashMap<>();
            for (Batcher.UpdateTask updateTask : updateTasks) {
                map.put(updateTask.task, updateTask.listener);
                priority = priority.sameOrAfter(updateTask.priority()) ? updateTask.priority() : priority;
            }
            return map;
        }
    }"""
if old not in text:
    print("patch: expected private TaskInputs block not found", file=sys.stderr)
    sys.exit(1)
path.write_text(text.replace(old, new, 1), encoding="utf-8")
print("OK:", path)
PY

echo "Patched TaskInputs → $MS"
