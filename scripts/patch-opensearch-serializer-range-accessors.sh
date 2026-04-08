#!/usr/bin/env bash
# Serializer: OpenSearch Range uses getters; Elassandra fork used public fields.
#
# Usage: ./scripts/patch-opensearch-serializer-range-accessors.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
F="$DEST/server/src/main/java/org/elassandra/cluster/Serializer.java"
[[ -f "$F" ]] || exit 0
perl -i -pe 's/\brange\.from\b/range.getFrom()/g; s/\brange\.to\b/range.getTo()/g; s/range\.includeFrom/range.isIncludeFrom()/g; s/range\.includeTo/range.isIncludeTo()/g' "$F"
echo "Patched Serializer range accessors → $F"
