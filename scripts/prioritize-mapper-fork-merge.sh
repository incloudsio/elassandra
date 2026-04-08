#!/usr/bin/env bash
# Rank forked mapper Java files by how often they mention CQL / Elassandra integration
# (higher score = merge sooner when rebasing onto org.opensearch.index.mapper).
#
# Usage: ./scripts/prioritize-mapper-fork-merge.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/server/src/main/java/org/elasticsearch/index/mapper"

if [[ ! -d "$SRC" ]]; then
  echo "Missing: $SRC" >&2
  exit 1
fi

echo -e "score\tfile"
while IFS= read -r -d '' f; do
  base="$(basename "$f")"
  # Count lines matching CQL / Elassandra hooks (coarse signal).
  n="$(grep -c -E 'CqlMapper|\bcql_|CQL_|org\.elassandra|strapdata|ElasticSecondaryIndex' "$f" 2>/dev/null || true)"
  echo -e "${n}\t${base}"
done < <(find "$SRC" -maxdepth 1 -name '*.java' -type f -print0) | sort -t$'\t' -k1 -nr
