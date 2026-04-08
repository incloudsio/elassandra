#!/usr/bin/env bash
# Copy Elassandra's forked org.elasticsearch.index.mapper sources next to an OpenSearch side-car checkout
# as a *reference tree* for manual 3-way merge into org.opensearch.index.mapper (does not replace OS files).
#
# Usage:
#   ./scripts/export-elassandra-mapper-fork-for-opensearch-merge.sh
#   OPENSEARCH_CLONE_DIR=/path/to/OpenSearch ./scripts/export-elassandra-mapper-fork-for-opensearch-merge.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${OPENSEARCH_CLONE_DIR:-$ROOT/../incloudsio-opensearch}"
SRC="$ROOT/server/src/main/java/org/elasticsearch/index/mapper"
OUT="$DEST/elassandra-mapper-fork-reference/org/elasticsearch/index/mapper"

if [[ ! -d "$SRC" ]]; then
  echo "Missing mapper fork: $SRC" >&2
  exit 1
fi
if [[ ! -d "$DEST/.git" ]]; then
  echo "OpenSearch clone not found at: $DEST" >&2
  exit 1
fi

mkdir -p "$OUT"
shopt -s nullglob
for f in "$SRC"/*.java; do
  base="$(basename "$f")"
  cp "$f" "$OUT/$base"
done
shopt -u nullglob

N="$(find "$OUT" -name '*.java' | wc -l | tr -d ' ')"
echo "Exported $N Java files to:"
echo "  $OUT"
echo "Diff or merge into: $DEST/server/src/main/java/org/opensearch/index/mapper/"
echo "Priority types for CqlMapper: ObjectMapper, FieldMapper, MappedFieldType, MapperService, TypeParsers, DocumentMapper."
