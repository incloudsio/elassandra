#!/usr/bin/env bash
# Sync org.elassandra.* into the OpenSearch side-car, rewrite imports, attach Elassandra Cassandra jar, run :server:compileJava.
# Remaining errors usually mean fork-only org.opensearch types (e.g. CqlMapper) are not merged yet.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Default side-car clone: incloudsio-opensearch (override with OPENSEARCH_CLONE_DIR).
DEST="${OPENSEARCH_CLONE_DIR:-$ROOT/../incloudsio-opensearch}"

if [[ -z "${JAVA_HOME:-}" ]]; then
  echo "Set JAVA_HOME to JDK 11+ (OpenSearch 1.3 requirement)." >&2
  exit 1
fi

"$ROOT/scripts/opensearch-sidecar-prepare.sh" "$DEST"
# Main + optional tests: set OPENSEARCH_SIDECAR_TASKS=":server:compileJava" to skip test compilation.
SIDECAR_TASKS="${OPENSEARCH_SIDECAR_TASKS:-:server:compileJava :test:framework:compileJava :server:compileTestJava}"
exec "$ROOT/scripts/gradlew-elassandra-sidecar.sh" ${SIDECAR_TASKS} --no-daemon "$@"
