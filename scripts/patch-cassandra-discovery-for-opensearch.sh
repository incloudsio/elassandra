#!/usr/bin/env bash
# OpenSearch-only fixes for synced org/elassandra/discovery/CassandraDiscovery.java:
# - AbstractLifecycleComponent has no Settings ctor
# - Discovery implements ClusterStatePublisher.publish(ClusterChangedEvent, ActionListener<Void>, AckListener)
#
# Usage: ./scripts/patch-cassandra-discovery-for-opensearch.sh "${OPENSEARCH_CLONE_DIR}"
# Run **after** rewrite-elassandra-imports-for-opensearch.sh
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
CD="$DEST/server/src/main/java/org/elassandra/discovery/CassandraDiscovery.java"
if [[ ! -f "$CD" ]]; then
  echo "No CassandraDiscovery.java at $CD" >&2
  exit 1
fi

perl -i -pe 's/super\(settings\)/super()/' "$CD"

# ES 6 DiscoveryNode.Role → OpenSearch DiscoveryNodeRole
perl -i -pe '
  s/import org\.opensearch\.cluster\.node\.DiscoveryNode\.Role;/import org.opensearch.cluster.node.DiscoveryNodeRole;/;
  s/\bImmutableSet<Role>/ImmutableSet<DiscoveryNodeRole>/g;
  s/\bRole\.MASTER\b/DiscoveryNodeRole.MASTER_ROLE/g;
  s/\bRole\.DATA\b/DiscoveryNodeRole.DATA_ROLE/g;
' "$CD"

# Discovery.FailedToCommitClusterStateException (ES) → coordination.FailedToCommitClusterStateException (OS)
if ! grep -q 'import org.opensearch.cluster.coordination.FailedToCommitClusterStateException;' "$CD"; then
  perl -i -0pe 's/(import org\.opensearch\.discovery\.Discovery;\n)/$1import org.opensearch.cluster.coordination.FailedToCommitClusterStateException;\n/' "$CD"
fi

# OpenSearch moved no-master block to NoMasterBlockService (DiscoverySettings no longer exposes it).
if ! grep -q 'import org.opensearch.cluster.coordination.NoMasterBlockService;' "$CD"; then
  perl -i -0pe 's/(import org\.opensearch\.discovery\.DiscoverySettings;\n)/$1import org.opensearch.cluster.coordination.NoMasterBlockService;\n/' "$CD"
fi
perl -i -pe 's/discoverySettings\.getNoMasterBlock\(\)/NoMasterBlockService.NO_MASTER_BLOCK_ALL/g' "$CD"

python3 << PY
import sys
from pathlib import Path
path = Path("$DEST/server/src/main/java/org/elassandra/discovery/CassandraDiscovery.java")
text = path.read_text(encoding="utf-8")
old = r'''    @Override
    public void publish(final ClusterChangedEvent clusterChangedEvent, final AckListener ackListener) {
        ClusterState previousClusterState = clusterChangedEvent.previousState();
        ClusterState newClusterState = clusterChangedEvent.state();

        long startTimeNS = System.nanoTime();
        try {
            if (clusterChangedEvent.schemaUpdate().updated()) {
                // update and broadcast the metadata through a CQL schema update + ack from participant nodes
                if (localNode().getId().equals(newClusterState.metadata().clusterUUID())) {
                    publishAsCoordinator(clusterChangedEvent, ackListener);
                } else {
                    publishAsParticipator(clusterChangedEvent, ackListener);
                }
            } else {
                // publish local cluster state update (for blocks, nodes or routing update)
                publishLocalUpdate(clusterChangedEvent, ackListener);
            }
        } catch (Exception e) {
            TimeValue executionTime = TimeValue.timeValueMillis(Math.max(0, TimeValue.nsecToMSec(System.nanoTime() - startTimeNS)));
            StringBuilder sb = new StringBuilder("failed to execute cluster state update in ").append(executionTime)
                    .append(", state:\nversion [")
                    .append(previousClusterState.version()).
                    append("], source [").append(clusterChangedEvent.source()).append("]\n");
            logger.warn(sb.toString(), e);
            throw new OpenSearchException(e);
        }
    }'''

new = r'''    @Override
    public void publish(
        final ClusterChangedEvent clusterChangedEvent,
        final org.opensearch.action.ActionListener<Void> publishListener,
        final AckListener ackListener) {
        ClusterState previousClusterState = clusterChangedEvent.previousState();
        ClusterState newClusterState = clusterChangedEvent.state();

        long startTimeNS = System.nanoTime();
        try {
            if (clusterChangedEvent.schemaUpdate().updated()) {
                // update and broadcast the metadata through a CQL schema update + ack from participant nodes
                if (localNode().getId().equals(newClusterState.metadata().clusterUUID())) {
                    publishAsCoordinator(clusterChangedEvent, ackListener);
                } else {
                    publishAsParticipator(clusterChangedEvent, ackListener);
                }
            } else {
                // publish local cluster state update (for blocks, nodes or routing update)
                publishLocalUpdate(clusterChangedEvent, ackListener);
            }
            publishListener.onResponse(null);
        } catch (Exception e) {
            TimeValue executionTime = TimeValue.timeValueMillis(Math.max(0, TimeValue.nsecToMSec(System.nanoTime() - startTimeNS)));
            StringBuilder sb = new StringBuilder("failed to execute cluster state update in ").append(executionTime)
                    .append(", state:\nversion [")
                    .append(previousClusterState.version()).
                    append("], source [").append(clusterChangedEvent.source()).append("]\n");
            logger.warn(sb.toString(), e);
            publishListener.onFailure(e);
            throw new OpenSearchException(e);
        }
    }'''

if old not in text:
    print("patch-cassandra-discovery: expected publish() block not found", file=sys.stderr)
    sys.exit(1)
path.write_text(text.replace(old, new, 1), encoding="utf-8")
print("Patched publish(...):", path)
PY

echo "Patched CassandraDiscovery for OpenSearch: $CD"
