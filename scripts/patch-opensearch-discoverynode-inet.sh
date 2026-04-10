#!/usr/bin/env bash
# Elassandra AbstractSearchStrategy uses DiscoveryNode#getNameAsInetAddress (ES 6.8 fork parity).
#
# Usage: ./scripts/patch-opensearch-discoverynode-inet.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
DN="$DEST/server/src/main/java/org/opensearch/cluster/node/DiscoveryNode.java"
[[ -f "$DN" ]] || exit 0

python3 - "$DN" <<'PY'
from pathlib import Path
import re
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
# Any existing implementation (Elassandra overlay or a prior patch) satisfies the fork.
if re.search(r"\n\s*public\s+[\w.]+\s+getNameAsInetAddress\s*\(", text):
    print("DiscoveryNode already has getNameAsInetAddress:", path)
    raise SystemExit(0)
# Insert before last closing brace of class — use getHostName anchor
needle = "    public String getHostName() {"
if needle not in text:
    print("patch: DiscoveryNode getHostName anchor not found", file=sys.stderr)
    sys.exit(1)
add = """    /**
     * Elassandra: parse node name as InetAddress when it is an IP literal (ES 6.8 fork parity).
     */
    public java.net.InetAddress getNameAsInetAddress() {
        try {
            return java.net.InetAddress.getByName(getName());
        } catch (java.net.UnknownHostException e) {
            throw new org.opensearch.OpenSearchException(e);
        }
    }

    public String getHostName() {"""
text = text.replace(needle, add, 1)
path.write_text(text, encoding="utf-8")
print("Patched DiscoveryNode getNameAsInetAddress →", path)
PY
