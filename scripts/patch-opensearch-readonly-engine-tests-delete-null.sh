#!/usr/bin/env bash
# ReadOnlyEngineTests: disambiguate delete(null) between Engine.delete(Delete) and ReadOnlyEngine.delete(DeleteByQuery).
#
# Usage: ./scripts/patch-opensearch-readonly-engine-tests-delete-null.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
F="$DEST/server/src/test/java/org/opensearch/index/engine/ReadOnlyEngineTests.java"
[[ -f "$F" ]] || exit 0

if grep -q 'Engine.Delete) null' "$F" 2>/dev/null; then
  echo "ReadOnlyEngineTests delete null already patched → $F"
  exit 0
fi

perl -i -pe 's/readOnlyEngine\.delete\(null\)/readOnlyEngine.delete((org.opensearch.index.engine.Engine.Delete) null)/' "$F"
echo "Patched ReadOnlyEngineTests delete(null) → $F"
