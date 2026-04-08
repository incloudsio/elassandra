#!/usr/bin/env bash
# After sync + rewrite-elassandra-imports, overlay OpenSearch-specific sources that diverge from the ES 6.8 fork:
# - token_range aggregation (TokenRangeAggregationBuilder / TokenRangeAggregatorFactory)
# - EnabledAttributeMapper (removed in stock OpenSearch; Elassandra internal mappers still reference it)
# - NumberFieldMapper: doc().addAll(...) when mapper overlay uses a pattern ParseContext.Document does not support
#
# Usage: ./scripts/patch-opensearch-elassandra-sidecar-templates.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${1:?OpenSearch clone root}"
TPL="$ROOT/scripts/templates/opensearch-sidecar"

if [[ ! -d "$TPL" ]]; then
  echo "Missing templates dir: $TPL" >&2
  exit 1
fi

if [[ -f "$TPL/TokenRangeAggregationBuilder.java" ]]; then
  mkdir -p "$DEST/server/src/main/java/org/elassandra/search/aggregations/bucket/token"
  cp "$TPL/TokenRangeAggregationBuilder.java" "$DEST/server/src/main/java/org/elassandra/search/aggregations/bucket/token/TokenRangeAggregationBuilder.java"
  echo "Overlay TokenRangeAggregationBuilder (OpenSearch API) → $DEST"
fi

if [[ -f "$TPL/TokenRangeAggregatorFactory.java" ]]; then
  mkdir -p "$DEST/server/src/main/java/org/opensearch/search/aggregations/bucket/range"
  cp "$TPL/TokenRangeAggregatorFactory.java" "$DEST/server/src/main/java/org/opensearch/search/aggregations/bucket/range/TokenRangeAggregatorFactory.java"
  echo "Overlay TokenRangeAggregatorFactory (OpenSearch API) → $DEST"
fi

if [[ -f "$TPL/TokenFieldMapper.java" ]]; then
  mkdir -p "$DEST/server/src/main/java/org/elassandra/index/mapper/internal"
  cp "$TPL/TokenFieldMapper.java" "$DEST/server/src/main/java/org/elassandra/index/mapper/internal/TokenFieldMapper.java"
  echo "Overlay TokenFieldMapper (OpenSearch API) → $DEST"
fi

if [[ -f "$TPL/HostFieldMapper.java" ]]; then
  mkdir -p "$DEST/server/src/main/java/org/elassandra/index/mapper/internal"
  cp "$TPL/HostFieldMapper.java" "$DEST/server/src/main/java/org/elassandra/index/mapper/internal/HostFieldMapper.java"
  echo "Overlay HostFieldMapper (OpenSearch API) → $DEST"
fi

EAM_SRC="$ROOT/server/src/main/java/org/elasticsearch/index/mapper/EnabledAttributeMapper.java"
EAM_DST="$DEST/server/src/main/java/org/opensearch/index/mapper/EnabledAttributeMapper.java"
if [[ -f "$EAM_SRC" ]]; then
  mkdir -p "$(dirname "$EAM_DST")"
  perl -pe 's/^package org\.elasticsearch\.index\.mapper/package org.opensearch.index.mapper/' "$EAM_SRC" > "$EAM_DST"
  echo "Wrote EnabledAttributeMapper stub → $EAM_DST"
fi

NM="$DEST/server/src/main/java/org/opensearch/index/mapper/NumberFieldMapper.java"
if [[ -f "$NM" ]] && grep -q 'context\.doc()\.addAll(' "$NM"; then
  perl -i -0777 -pe 's/context\.doc\(\)\.addAll\(([^;]+)\);/for (org.apache.lucene.document.Field f : $1) { context.doc().add(f); }/s' "$NM"
  echo "Patched NumberFieldMapper doc().addAll → for-loop: $NM"
fi

CS="$DEST/server/src/main/java/org/opensearch/cluster/service/ClusterService.java"
if [[ -f "$CS" ]] && ! grep -q 'SETTING_SYSTEM_SYNCHRONOUS_REFRESH' "$CS"; then
  perl -i -0pe 's/(public static int replicationFactor\(String keyspace\) \{\s*return 1;\s*\})/$1\n\n    public static final String SETTING_SYSTEM_SYNCHRONOUS_REFRESH = "es.synchronous_refresh";/s' "$CS"
  echo "Added SETTING_SYSTEM_SYNCHRONOUS_REFRESH stub → $CS"
fi
