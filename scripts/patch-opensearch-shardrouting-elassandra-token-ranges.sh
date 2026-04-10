#!/usr/bin/env bash
# Elassandra: ShardRouting carries Cassandra token ranges; stock OpenSearch 1.3 removed them.
# Extends the primary constructor with an optional token-range field and adds ShardRouting.newElassandra(...)
# for AbstractSearchStrategy (fork parity).
#
# Usage: ./scripts/patch-opensearch-shardrouting-elassandra-token-ranges.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
SR="$DEST/server/src/main/java/org/opensearch/cluster/routing/ShardRouting.java"
[[ -f "$SR" ]] || exit 0

if grep -q 'ShardRouting.newElassandra' "$SR"; then
  echo "ShardRouting Elassandra token ranges already patched: $SR"
  exit 0
fi

python3 - "$SR" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

if "newElassandra" in text:
    print("ShardRouting already patched:", path)
    raise SystemExit(0)


def patch_new_calls(s: str) -> str:
    out = []
    idx = 0
    while True:
        pos = s.find("new ShardRouting(", idx)
        if pos == -1:
            out.append(s[idx:])
            break
        out.append(s[idx:pos])
        start = pos
        j = pos + len("new ShardRouting(")
        depth = 1
        while j < len(s) and depth > 0:
            if s[j] == "(":
                depth += 1
            elif s[j] == ")":
                depth -= 1
            j += 1
        call = s[start:j]
        if "elassandraTokenRanges" not in call and not call.rstrip().endswith(", null)"):
            call = call[:-1] + ", null)"
        out.append(call)
        idx = j
    return "".join(out)


# Imports
if "org.apache.cassandra.dht.Range" not in text:
    text = text.replace(
        "import org.opensearch.index.shard.ShardId;\n",
        "import org.opensearch.index.shard.ShardId;\n\n"
        "import java.util.Collection;\n"
        "import org.apache.cassandra.dht.Range;\n"
        "import org.apache.cassandra.dht.Token;\n",
        1,
    )

needle_field = """    @Nullable
    private final ShardRouting targetRelocatingShard;

    /**
     * A constructor to internally create shard routing instances"""
if needle_field not in text:
    print("ShardRouting: targetRelocatingShard anchor not found", file=sys.stderr)
    sys.exit(1)
text = text.replace(
    needle_field,
    """    @Nullable
    private final ShardRouting targetRelocatingShard;

    /** Elassandra: Cassandra token ranges for this routing (side-car / tests; not on wire). */
    @Nullable
    private transient Collection<Range<Token>> elassandraTokenRanges = null;

    /**
     * A constructor to internally create shard routing instances""",
    1,
)

old_sig = """    ShardRouting(
        ShardId shardId,
        String currentNodeId,
        String relocatingNodeId,
        boolean primary,
        ShardRoutingState state,
        RecoverySource recoverySource,
        UnassignedInfo unassignedInfo,
        AllocationId allocationId,
        long expectedShardSize
    ) {"""
new_sig = """    ShardRouting(
        ShardId shardId,
        String currentNodeId,
        String relocatingNodeId,
        boolean primary,
        ShardRoutingState state,
        RecoverySource recoverySource,
        UnassignedInfo unassignedInfo,
        AllocationId allocationId,
        long expectedShardSize,
        @Nullable Collection<Range<Token>> elassandraTokenRanges
    ) {"""
if old_sig not in text:
    print("ShardRouting: constructor signature not found", file=sys.stderr)
    sys.exit(1)
text = text.replace(old_sig, new_sig, 1)

old_assign = """        this.expectedShardSize = expectedShardSize;
        this.targetRelocatingShard = initializeTargetRelocatingShard();
        this.asList = Collections.singletonList(this);"""
new_assign = """        this.expectedShardSize = expectedShardSize;
        this.elassandraTokenRanges = elassandraTokenRanges;
        this.targetRelocatingShard = initializeTargetRelocatingShard();
        this.asList = Collections.singletonList(this);"""
if old_assign not in text:
    print("ShardRouting: constructor assignment anchor not found", file=sys.stderr)
    sys.exit(1)
text = text.replace(old_assign, new_assign, 1)

text = patch_new_calls(text)

factory = """

    /** Elassandra: Cassandra token ranges attached to this routing (empty if none). */
    public Collection<Range<Token>> tokenRanges() {
        return elassandraTokenRanges == null ? java.util.Collections.emptyList() : elassandraTokenRanges;
    }

    /**
     * Elassandra synthetic shard routing (same semantics as the ES 6.8 fork 6-arg constructor).
     */
    public static ShardRouting newElassandra(
        ShardId shardId,
        String currentNodeId,
        boolean primary,
        ShardRoutingState state,
        UnassignedInfo unassignedInfo,
        Collection<Range<Token>> tokenRanges
    ) {
        RecoverySource recoverySource =
            (!primary)
                ? PeerRecoverySource.INSTANCE
                : ((state == ShardRoutingState.UNASSIGNED || state == ShardRoutingState.INITIALIZING)
                    ? RecoverySource.LocalShardsRecoverySource.INSTANCE
                    : null);
        UnassignedInfo ui =
            (state == ShardRoutingState.UNASSIGNED || state == ShardRoutingState.INITIALIZING) ? unassignedInfo : null;
        AllocationId aid =
            (state == ShardRoutingState.STARTED || state == ShardRoutingState.INITIALIZING)
                ? AllocationId.newInitializing()
                : null;
        return new ShardRouting(
            shardId,
            currentNodeId,
            null,
            primary,
            state,
            recoverySource,
            ui,
            aid,
            UNAVAILABLE_EXPECTED_SHARD_SIZE,
            tokenRanges
        );
    }
"""
idx = text.rfind("\n}")
text = text[:idx] + factory + text[idx:]

path.write_text(text, encoding="utf-8")
print("Patched", path)
PY
