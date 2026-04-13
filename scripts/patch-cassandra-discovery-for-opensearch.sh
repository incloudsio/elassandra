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
import re
import sys
from pathlib import Path

path = Path("$DEST/server/src/main/java/org/elassandra/discovery/CassandraDiscovery.java")
text = path.read_text(encoding="utf-8")
original = text

old_sig = "public void publish(final ClusterChangedEvent clusterChangedEvent, final AckListener ackListener) {"
new_sig = """public void publish(
        final ClusterChangedEvent clusterChangedEvent,
        final org.opensearch.action.ActionListener<Void> publishListener,
        final AckListener ackListener) {"""

if new_sig not in text:
    if old_sig not in text:
        print("patch-cassandra-discovery: publish() signature not found", file=sys.stderr)
        sys.exit(1)
    text = text.replace(old_sig, new_sig, 1)

if "publishListener.onResponse(null);" not in text:
    commit_line = "            ackListener.onCommit(TimeValue.timeValueNanos(System.nanoTime() - startTimeNS));"
    if commit_line in text:
        text = text.replace(commit_line, commit_line + "\n            publishListener.onResponse(null);", 1)
    else:
        response_line = "            publishListener.onResponse(null);"
        catch_marker = "        } catch (Exception e) {"
        if response_line not in text and catch_marker in text:
            text = text.replace(catch_marker, "            publishListener.onResponse(null);\n" + catch_marker, 1)

failure_line = "            publishListener.onFailure(e);"
if failure_line not in text:
    pattern = re.compile(r'(            logger\.warn\(sb\.toString\(\), e\);\n)(            throw new OpenSearchException\(e\);)')
    text, count = pattern.subn(r'\1            publishListener.onFailure(e);\n\2', text, count=1)
    if count == 0:
        print("patch-cassandra-discovery: failed to wire publishListener.onFailure", file=sys.stderr)
        sys.exit(1)

if text == original:
    print("CassandraDiscovery publish(...) already OpenSearch-compatible:", path)
else:
    path.write_text(text, encoding="utf-8")
    print("Patched publish(...):", path)
PY

echo "Patched CassandraDiscovery for OpenSearch: $CD"
