#!/usr/bin/env bash
# Insert Elassandra-compatible Node#activate() (delegates to start) — required by org.apache.cassandra.service.ElassandraDaemon.
# Idempotent: skips if the Elassandra marker is already present.
# Usage: ./scripts/patch-opensearch-node-elassandra-activate.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
NODE="$DEST/server/src/main/java/org/opensearch/node/Node.java"
if [[ ! -f "$NODE" ]]; then
  echo "Node.java not found: $NODE" >&2
  exit 1
fi
if grep -q "Elassandra: phased activation hook" "$NODE" 2>/dev/null; then
  echo "Node.java already patched for Elassandra activate()"
  exit 0
fi

python3 - "$NODE" << 'PY'
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    text = f.read()
needle = "    public Node start() throws NodeValidationException {"
if needle not in text:
    print("Expected marker not found: public Node start()", file=sys.stderr)
    sys.exit(1)
insert = """    /**
     * Elassandra: phased activation hook (ported from Elasticsearch 6.8 fork).
     * Delegates to {@link #start()} for OpenSearch 1.3.
     */
    public Node activate() throws NodeValidationException {
        return start();
    }

"""
text = text.replace(needle, insert + needle, 1)
with open(path, "w", encoding="utf-8") as f:
    f.write(text)
print("Patched Node.java with Elassandra activate() ->", path)
PY
