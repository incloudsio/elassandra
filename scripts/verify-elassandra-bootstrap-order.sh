#!/usr/bin/env bash
# Fail if ElassandraDaemon init calls node.start() before node.activate() (gateway must run first on ES Node).
# OpenSearch side-car: patch-opensearch-node-elassandra-activate.sh makes activate() delegate to start();
#   init may still list activate(); start() — second start() is a lifecycle no-op on OpenSearch Node.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

check_file() {
  local label="$1" f="$2"
  if [[ ! -f "$f" ]]; then
    echo "verify: missing $f" >&2
    return 1
  fi
  local line_a line_s
  line_a=$(grep -n 'this\.node\.activate();' "$f" | head -1 | cut -d: -f1 || true)
  line_s=$(grep -n 'this\.node\.start();' "$f" | head -1 | cut -d: -f1 || true)
  if [[ -z "$line_a" || -z "$line_s" ]]; then
    echo "verify: $label — need both this.node.activate() and this.node.start() in $f" >&2
    return 1
  fi
  if [[ "$line_a" -ge "$line_s" ]]; then
    echo "verify: $label — first start() (line $line_s) is before or same as activate() (line $line_a) in $f" >&2
    return 1
  fi
  echo "verify: $label OK — activate() line $line_a before start() line $line_s ($f)"
}

check_file "server" "$ROOT/server/src/main/java/org/apache/cassandra/service/ElassandraDaemon.java"
check_file "merged" "$ROOT/scripts/templates/ElassandraDaemon-opensearch-merged.java"
