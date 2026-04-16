#!/usr/bin/env bash
# Copy minimal fork-only types into the OpenSearch side-car as org.opensearch.* (before full engine rebase).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${1:-$ROOT/../incloudsio-opensearch}"
MAPPER="$DEST/server/src/main/java/org/opensearch/index/mapper"
AGG="$DEST/server/src/main/java/org/opensearch/search/aggregations"
SRC_CQL="$ROOT/server/src/main/java/org/elasticsearch/index/mapper/CqlMapper.java"
SRC_DPC="$ROOT/server/src/main/java/org/elasticsearch/index/mapper/DocumentParserCompat.java"
SRC_AGG="$ROOT/server/src/main/java/org/elasticsearch/search/aggregations/AggregationMetaDataBuilder.java"

if [[ ! -f "$SRC_CQL" ]] && [[ -f "$ROOT/server/src/main/java/org/opensearch/index/mapper/CqlMapper.java" ]]; then
  SRC_CQL="$ROOT/server/src/main/java/org/opensearch/index/mapper/CqlMapper.java"
fi
if [[ ! -f "$SRC_DPC" ]] && [[ -f "$ROOT/server/src/main/java/org/opensearch/index/mapper/DocumentParserCompat.java" ]]; then
  SRC_DPC="$ROOT/server/src/main/java/org/opensearch/index/mapper/DocumentParserCompat.java"
fi
if [[ ! -f "$SRC_AGG" ]] && [[ -f "$ROOT/server/src/main/java/org/opensearch/search/aggregations/AggregationMetaDataBuilder.java" ]]; then
  SRC_AGG="$ROOT/server/src/main/java/org/opensearch/search/aggregations/AggregationMetaDataBuilder.java"
fi

if [[ ! -f "$SRC_CQL" ]]; then
  echo "Missing $SRC_CQL" >&2
  exit 1
fi
mkdir -p "$MAPPER"
sed -e 's/^package org\.elasticsearch\.index\.mapper;/package org.opensearch.index.mapper;/' \
    -e 's/^package org\.opensearch\.index\.mapper;/package org.opensearch.index.mapper;/' \
    "$SRC_CQL" > "$MAPPER/CqlMapper.java"
echo "Wrote $MAPPER/CqlMapper.java"

if [[ -f "$SRC_DPC" ]]; then
  sed -e 's/^package org\.elasticsearch\.index\.mapper;/package org.opensearch.index.mapper;/' \
      -e 's/^package org\.opensearch\.index\.mapper;/package org.opensearch.index.mapper;/' \
      "$SRC_DPC" > "$MAPPER/DocumentParserCompat.java"
  echo "Wrote $MAPPER/DocumentParserCompat.java"
fi

if [[ -f "$SRC_AGG" ]]; then
  mkdir -p "$AGG"
  sed -e 's/^package org\.elasticsearch\.search\.aggregations;/package org.opensearch.search.aggregations;/' \
      -e 's/^package org\.opensearch\.search\.aggregations;/package org.opensearch.search.aggregations;/' \
      "$SRC_AGG" > "$AGG/AggregationMetaDataBuilder.java"
  echo "Wrote $AGG/AggregationMetaDataBuilder.java"
fi
