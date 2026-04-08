#!/usr/bin/env bash
# Copy Elassandra's forked org.elasticsearch.index.mapper sources into this repo's build/ tree as
# org.opensearch.index.mapper, then run the same import rewrites as the side-car (does not compile
# as-is — use for diff/review before merging into an OpenSearch clone).
#
# Output (default): build/elassandra-mapper-staged-opensearch/server/src/main/java/org/opensearch/index/mapper/
#
# Usage:
#   ./scripts/stage-elassandra-mapper-fork-as-opensearch.sh
#   ELASSANDRA_MAPPER_STAGE=/tmp/stage ./scripts/stage-elassandra-mapper-fork-as-opensearch.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$ROOT/server/src/main/java/org/elasticsearch/index/mapper"
BASE="${ELASSANDRA_MAPPER_STAGE:-$ROOT/build/elassandra-mapper-staged-opensearch}"
OUT="$BASE/server/src/main/java/org/opensearch/index/mapper"

if [[ ! -d "$SRC" ]]; then
  echo "Missing mapper fork: $SRC" >&2
  exit 1
fi

mkdir -p "$OUT"
shopt -s nullglob
for f in "$SRC"/*.java; do
  cp "$f" "$OUT/$(basename "$f")"
done
shopt -u nullglob

while IFS= read -r -d '' f; do
  perl -i -pe 's/^package\s+org\.elasticsearch\.index\.mapper\s*;/package org.opensearch.index.mapper;/' "$f"
done < <(find "$OUT" -name '*.java' -type f -print0)

"$SCRIPT_DIR/rewrite-engine-java-for-opensearch.sh" "$OUT"

N="$(find "$OUT" -name '*.java' | wc -l | tr -d ' ')"
echo "Staged $N Java files under:"
echo "  $OUT"
echo "Diff against upstream: <OpenSearch>/server/src/main/java/org/opensearch/index/mapper/"
echo "Priority list: ./scripts/prioritize-mapper-fork-merge.sh"
