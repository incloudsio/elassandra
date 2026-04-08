#!/usr/bin/env bash
# Copy minimal fork-only types into the OpenSearch side-car as org.opensearch.* (before full engine rebase).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${1:-$ROOT/../opensearch-upstream}"
MAPPER="$DEST/server/src/main/java/org/opensearch/index/mapper"
AGG="$DEST/server/src/main/java/org/opensearch/search/aggregations"
SRC_CQL="$ROOT/server/src/main/java/org/elasticsearch/index/mapper/CqlMapper.java"
SRC_DPC="$ROOT/server/src/main/java/org/elasticsearch/index/mapper/DocumentParserCompat.java"
SRC_AGG="$ROOT/server/src/main/java/org/elasticsearch/search/aggregations/AggregationMetaDataBuilder.java"

if [[ ! -f "$SRC_CQL" ]]; then
  echo "Missing $SRC_CQL" >&2
  exit 1
fi
mkdir -p "$MAPPER"
sed 's/^package org\.elasticsearch\.index\.mapper;/package org.opensearch.index.mapper;/' "$SRC_CQL" > "$MAPPER/CqlMapper.java"
echo "Wrote $MAPPER/CqlMapper.java"

if [[ -f "$SRC_DPC" ]]; then
  sed 's/^package org\.elasticsearch\.index\.mapper;/package org.opensearch.index.mapper;/' "$SRC_DPC" > "$MAPPER/DocumentParserCompat.java"
  echo "Wrote $MAPPER/DocumentParserCompat.java"
fi

if [[ -f "$SRC_AGG" ]]; then
  mkdir -p "$AGG"
  sed 's/^package org\.elasticsearch\.search\.aggregations;/package org.opensearch.search.aggregations;/' "$SRC_AGG" > "$AGG/AggregationMetaDataBuilder.java"
  echo "Wrote $AGG/AggregationMetaDataBuilder.java"
fi
