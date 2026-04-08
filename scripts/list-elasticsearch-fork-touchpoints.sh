#!/usr/bin/env bash
# List Java files under server/src/main/java/org/elasticsearch likely carrying Elassandra-specific edits.
# Use when rebasing the engine fork onto OpenSearch (see docs/.../opensearch_porting_guide.rst).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ES_JAVA="$ROOT/server/src/main/java/org/elasticsearch"
if [[ ! -d "$ES_JAVA" ]]; then
  echo "Missing $ES_JAVA" >&2
  exit 1
fi

echo "# Files mentioning elassandra / strapdata / Elassandra (case-insensitive), under org/elasticsearch:"
echo "# ---"
if command -v rg >/dev/null 2>&1; then
  rg -l -i 'elassandra|strapdata' "$ES_JAVA" | sort
else
  grep -RIl -i -e elassandra -e strapdata "$ES_JAVA" | sort
fi
