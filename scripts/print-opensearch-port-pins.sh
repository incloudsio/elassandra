#!/usr/bin/env bash
# Print OpenSearch port target pins from buildSrc/version.properties (no Gradle required).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROPS="$ROOT/buildSrc/version.properties"
grep -E '^[[:space:]]*(opensearch_port|lucene_opensearch)[[:space:]]*=' "$PROPS" | sed 's/^[[:space:]]*//'
