#!/usr/bin/env bash
# Replace deprecated test node/script settings that trip OpenSearchTestCase#ensureNoWarnings (OS 1.3+).
#
# Usage: ./scripts/patch-opensearch-opens-search-single-node-nondeprecated-settings.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
F="$DEST/test/framework/src/main/java/org/opensearch/test/OpenSearchSingleNodeTestCase.java"
[[ -f "$F" ]] || exit 0

perl -i -0777 -pe '
  s/                        \.put\("node\.data", true\)\n/                        .put("node.roles", "data")\n/g;
  s/                        \.put\(ScriptService\.SCRIPT_GENERAL_MAX_COMPILATIONS_RATE_SETTING\.getKey\(\), "[^"]*"\)\n//g;
' "$F"
echo "Patched OpenSearchSingleNodeTestCase non-deprecated settings → $F"
