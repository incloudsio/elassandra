#!/usr/bin/env bash
# Apply Elassandra → OpenSearch 1.3 import and API symbol rewrites to arbitrary Java trees
# (nested metrics packages, IndexMetaData → IndexMetadata, ElasticsearchException, TotalHits.value, etc.).
#
# Usage:
#   ./scripts/rewrite-engine-java-for-opensearch.sh <directory>
#   ./scripts/rewrite-engine-java-for-opensearch.sh --file <path>
set -euo pipefail

rewrite_file() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  perl -i -pe '
      s/org\.elasticsearch\.common\.lucene\.index\.ElasticsearchDirectoryReader/org.opensearch.common.lucene.index.OpenSearchDirectoryReader/g;
      s/\bElasticsearchDirectoryReader\b/OpenSearchDirectoryReader/g;
      s/org\.elasticsearch\.ElasticsearchParseException/org.opensearch.OpenSearchParseException/g;
      s/org\.elasticsearch\.ElasticsearchGenerationException/org.opensearch.OpenSearchGenerationException/g;
      s/org\.elasticsearch\.cluster\.metadata\.IndexMetaData/org.opensearch.cluster.metadata.IndexMetadata/g;
      s/org\.elasticsearch\.cluster\.metadata\.MappingMetaData/org.opensearch.cluster.metadata.MappingMetadata/g;
      s/org\.elasticsearch\.cluster\.metadata\.MetaData([^a-zA-Z])/org.opensearch.cluster.metadata.Metadata$1/g;
      s/org\.elasticsearch\.search\.aggregations\.metrics\.min\./org.opensearch.search.aggregations.metrics./g;
      s/org\.elasticsearch\.search\.aggregations\.metrics\.max\./org.opensearch.search.aggregations.metrics./g;
      s/org\.elasticsearch\.search\.aggregations\.metrics\.avg\./org.opensearch.search.aggregations.metrics./g;
      s/org\.elasticsearch\.search\.aggregations\.metrics\.sum\./org.opensearch.search.aggregations.metrics./g;
      s/org\.elasticsearch\.search\.aggregations\.metrics\.stats\./org.opensearch.search.aggregations.metrics./g;
      s/org\.elasticsearch\.search\.aggregations\.metrics\.percentiles\.hdr\./org.opensearch.search.aggregations.metrics./g;
      s/org\.elasticsearch\.search\.aggregations\.metrics\.percentiles\.tdigest\./org.opensearch.search.aggregations.metrics./g;
      s/org\.elasticsearch\.search\.aggregations\.metrics\.percentiles\.PercentilesAggregationBuilder/org.opensearch.search.aggregations.metrics.PercentilesAggregationBuilder/g;
      s/org\.elasticsearch\.search\.aggregations\.metrics\.percentiles\.Percentile\b/org.opensearch.search.aggregations.metrics.Percentile/g;
      s/org\.elasticsearch\.search\.aggregations\.metrics\.percentiles\.Percentiles\b/org.opensearch.search.aggregations.metrics.Percentiles/g;
      s/org\.elasticsearch\.ElasticsearchException/org.opensearch.OpenSearchException/g;
      s/org\.elasticsearch/org.opensearch/g;
      s/org\.opensearch\.ElasticsearchParseException/org.opensearch.OpenSearchParseException/g;
      s/org\.opensearch\.ElasticsearchGenerationException/org.opensearch.OpenSearchGenerationException/g;
      s/\bElasticsearchParseException\b/OpenSearchParseException/g;
      s/\bElasticsearchGenerationException\b/OpenSearchGenerationException/g;
      s/\bElasticsearchException\b/OpenSearchException/g;
      s/resp\.getHits\(\)\.getTotalHits\(\)(?!\.value)/resp.getHits().getTotalHits().value/g;
      s/^import org\.opensearch\.common\.component\.AbstractComponent;\r?\n//m;
      s/org\.opensearch\.cluster\.metadata\.IndexMetaData/org.opensearch.cluster.metadata.IndexMetadata/g;
      s/org\.opensearch\.cluster\.metadata\.MappingMetaData/org.opensearch.cluster.metadata.MappingMetadata/g;
      s/\bIndexMetaData\b/IndexMetadata/g;
      s/\bMappingMetaData\b/MappingMetadata/g;
      s/\bMetaData\.Builder\b/Metadata.Builder/g;
      s/\bMetaData\b/Metadata/g;
      s/\.metaData\(\)/.metadata()/g;
      s/\.metaData\(/\.metadata\(/g;
      s/\.getIndexMetaData\(\)/.getIndexMetadata()/g;
    ' "$f"
}

rewrite_tree() {
  local dir="$1"
  [[ -d "$dir" ]] || return 0
  while IFS= read -r -d '' f; do
    rewrite_file "$f"
  done < <(find "$dir" -name '*.java' -type f -print0)
}

if [[ "${1:-}" == "--file" ]]; then
  [[ -n "${2:-}" ]] || { echo "usage: $0 --file <path>" >&2; exit 1; }
  rewrite_file "$2"
elif [[ -n "${1:-}" && -d "$1" ]]; then
  rewrite_tree "$1"
else
  echo "usage: $0 <directory-with-java> | --file <path>" >&2
  exit 1
fi
