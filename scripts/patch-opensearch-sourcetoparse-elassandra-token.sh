#!/usr/bin/env bash
# Elassandra fork parity for SourceToParse: mutable routing + Cassandra row token (_token).
# Stock OpenSearch uses final routing; Elassandra sets routing/token after construction.
#
# Usage: ./scripts/patch-opensearch-sourcetoparse-elassandra-token.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${1:?OpenSearch clone root}"
ST="$DEST/server/src/main/java/org/opensearch/index/mapper/SourceToParse.java"
TPL="$ROOT/scripts/templates/opensearch-sidecar/SourceToParse.java"
if [[ ! -f "$TPL" ]]; then
  echo "Missing template $TPL" >&2
  exit 1
fi
cp "$TPL" "$ST"
echo "Wrote Elassandra SourceToParse → $ST"
