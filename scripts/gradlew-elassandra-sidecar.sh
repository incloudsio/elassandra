#!/usr/bin/env bash
# Run OpenSearch Gradle with the Elassandra Cassandra jar + opensearch-sidecar-elassandra.init.gradle.
# Required when the side-car checkout contains org.elassandra.* (:server:compileJava checks for elassandra-cassandra-*.jar).
#
# Usage (from elassandra repo root):
#   ./scripts/gradlew-elassandra-sidecar.sh :server:compileJava --no-daemon
#   OPENSEARCH_CLONE_DIR=/path/to/incloudsio-opensearch ./scripts/gradlew-elassandra-sidecar.sh :server:test --tests 'org.elassandra.Foo' --no-daemon
#
# Build the jar in this repo first (or set ELASSANDRA_CASSANDRA_JAR to an existing elassandra-cassandra-*.jar):
#   ./scripts/build-elassandra-cassandra-jar.sh
#
# Does not run opensearch-sidecar-prepare.sh; run that after changing Elassandra sources or patches.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${OPENSEARCH_CLONE_DIR:-$ROOT/../incloudsio-opensearch}"
INIT_GRADLE="$ROOT/gradle/opensearch-sidecar-elassandra.init.gradle"

if [[ -z "${JAVA_HOME:-}" ]]; then
  echo "Set JAVA_HOME to JDK 11+ (OpenSearch 1.3 requirement)." >&2
  exit 1
fi

if [[ ! -f "$DEST/gradlew" ]]; then
  echo "OpenSearch clone not found at: $DEST (set OPENSEARCH_CLONE_DIR)" >&2
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
  echo "Building Cassandra jar (or set ELASSANDRA_CASSANDRA_JAR)..." >&2
  JAR="$("$ROOT/scripts/build-elassandra-cassandra-jar.sh")"
fi

if [[ ! -f "$JAR" ]]; then
  echo "Cassandra jar not found: $JAR" >&2
  exit 1
fi

export GRADLE_OPTS="${GRADLE_OPTS:-} -Delassandra.cassandra.jar=$JAR"
cd "$DEST"
exec ./gradlew -I "$INIT_GRADLE" "$@"
