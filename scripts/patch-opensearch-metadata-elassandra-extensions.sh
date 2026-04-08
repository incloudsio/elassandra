#!/usr/bin/env bash
# Add Elassandra-only helpers used by discovery/schema code:
# - Metadata#x2() fingerprint (clusterUUID/version)
# - Metadata.Builder#incrementVersion() for coordinator publish path
#
# Usage: ./scripts/patch-opensearch-metadata-elassandra-extensions.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
MD="$DEST/server/src/main/java/org/opensearch/cluster/metadata/Metadata.java"
if [[ ! -f "$MD" ]]; then
  echo "No Metadata.java at $MD" >&2
  exit 1
fi

if grep -q 'Elassandra metadata fingerprint' "$MD"; then
  echo "Already patched: $MD"
  exit 0
fi

perl -i -0pe '
  s/(public String clusterUUID\(\) \{\s*return this\.clusterUUID;\s*\})/$1\n\n    \/\*\*\n     * Elassandra metadata fingerprint (cluster UUID + version), used in gossip and logging.\n     *\/\n    public String x2\(\) {\n        return clusterUUID + "\/" + version;\n    }/s
' "$MD"

perl -i -0pe '
  s/(public Builder version\(long version\) \{\s*this\.version = version;\s*return this;\s*\})/$1\n\n        \/\*\*\n         * Elassandra: bump global metadata version (coordinator\/PAXOS path).\n         *\/\n        public Builder incrementVersion\(\) {\n            this.version = this.version + 1;\n            return this;\n        }/s
' "$MD"

echo "Patched Metadata Elassandra extensions → $MD"
