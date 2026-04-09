#!/usr/bin/env bash
# Sync org.elassandra.* into the OpenSearch side-car, rewrite imports, attach Elassandra Cassandra jar, run :server:compileJava.
# Remaining errors usually mean fork-only org.opensearch types (e.g. CqlMapper) are not merged yet.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Default side-car clone: incloudsio-opensearch (override with OPENSEARCH_CLONE_DIR).
DEST="${OPENSEARCH_CLONE_DIR:-$ROOT/../incloudsio-opensearch}"
INIT_GRADLE="$ROOT/gradle/opensearch-sidecar-elassandra.init.gradle"

if [[ -z "${JAVA_HOME:-}" ]]; then
  echo "Set JAVA_HOME to JDK 11+ (OpenSearch 1.3 requirement)." >&2
  exit 1
fi

JAR="${ELASSANDRA_CASSANDRA_JAR:-}"
if [[ -z "$JAR" ]]; then
  VER="$(grep '^cassandra[[:space:]]*=' "$ROOT/buildSrc/version.properties" | head -1 | sed 's/.*=[[:space:]]*//' | tr -d '\r')"
  JAR="$ROOT/server/cassandra/build/elassandra-cassandra-${VER}.jar"
fi

if [[ ! -f "$JAR" ]]; then
  if [[ "${SKIP_ELASSANDRA_CASSANDRA_JAR:-}" == "1" ]]; then
    echo "SKIP_ELASSANDRA_CASSANDRA_JAR=1 but jar missing: $JAR" >&2
    exit 1
  fi
  echo "Building Cassandra jar (or set ELASSANDRA_CASSANDRA_JAR to an existing jar)..." >&2
  JAR="$("$ROOT/scripts/build-elassandra-cassandra-jar.sh")"
fi

if [[ ! -f "$JAR" ]]; then
  echo "Cassandra jar not found: $JAR" >&2
  exit 1
fi

"$ROOT/scripts/opensearch-sidecar-prepare.sh" "$DEST"
cd "$DEST"
# OpenSearch's gradlew often does not forward CLI -D to the build JVM; use GRADLE_OPTS (see gradle/opensearch-sidecar-elassandra.init.gradle).
export GRADLE_OPTS="${GRADLE_OPTS:-} -Delassandra.cassandra.jar=$JAR"
# Main + optional tests: set OPENSEARCH_SIDECAR_TASKS=":server:compileJava" to skip test compilation.
SIDECAR_TASKS="${OPENSEARCH_SIDECAR_TASKS:-:server:compileJava :test:framework:compileJava :server:compileTestJava}"
exec ./gradlew -I "$INIT_GRADLE" ${SIDECAR_TASKS} --no-daemon "$@"
