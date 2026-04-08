#!/usr/bin/env bash
# Elassandra uses DiscoveryNode#uuid() for Cassandra host ids; OpenSearch only has getId().
# Adds uuid() for side-car compilation (stable UUID derived from getId()).
#
# Usage: ./scripts/patch-opensearch-discovery-node-elassandra-uuid.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
DN="$DEST/server/src/main/java/org/opensearch/cluster/node/DiscoveryNode.java"
[[ -f "$DN" ]] || exit 0
if grep -q "Elassandra: UUID for Cassandra" "$DN"; then
  echo "DiscoveryNode uuid() already patched: $DN"
  exit 0
fi
python3 - "$DN" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
t = path.read_text(encoding="utf-8")
needle = """    public String getEphemeralId() {
        return ephemeralId;
    }

    /**
     * The name of the node.
     */
    public String getName() {
        return this.nodeName;
    }
"""
if "Elassandra: UUID for Cassandra" in t:
    print("already patched:", path)
    raise SystemExit(0)
if needle not in t:
    print("DiscoveryNode: anchor not found", file=sys.stderr)
    sys.exit(1)
replacement = """    public String getEphemeralId() {
        return ephemeralId;
    }

    /**
     * Elassandra: UUID for Cassandra token metadata / routing (fork parity). OpenSearch node ids are opaque strings;
     * this derives a stable UUID from {@link #getId()} for compile-time compatibility.
     */
    public java.util.UUID uuid() {
        try {
            return java.util.UUID.fromString(getId());
        } catch (IllegalArgumentException e) {
            return java.util.UUID.nameUUIDFromBytes(getId().getBytes(java.nio.charset.StandardCharsets.UTF_8));
        }
    }

    /**
     * The name of the node.
     */
    public String getName() {
        return this.nodeName;
    }
"""
path.write_text(t.replace(needle, replacement, 1), encoding="utf-8")
print("Patched DiscoveryNode.uuid() →", path)
PY
