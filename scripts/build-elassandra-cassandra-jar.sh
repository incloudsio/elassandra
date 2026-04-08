#!/usr/bin/env bash
# Build server/cassandra/build/elassandra-cassandra-<version>.jar via Ant (Gradle :cassandra-jar).
# Prints the absolute jar path as the only stdout line (logs on stderr).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VER="$(grep '^cassandra[[:space:]]*=' "$ROOT/buildSrc/version.properties" | head -1 | sed 's/.*=[[:space:]]*//' | tr -d '\r')"
JAR="$ROOT/server/cassandra/build/elassandra-cassandra-${VER}.jar"
if [[ -f "$JAR" ]] && [[ "${ELASSANDRA_CASSANDRA_JAR_FORCE_REBUILD:-}" != "1" ]]; then
  echo "Using existing $(basename "$JAR")" >&2
  echo "$(cd "$(dirname "$JAR")" && pwd)/$(basename "$JAR")"
  exit 0
fi
if [[ -z "${JAVA11_HOME:-}" ]]; then
  if command -v /usr/libexec/java_home >/dev/null 2>&1; then
    export JAVA11_HOME="$(/usr/libexec/java_home -v 11 2>/dev/null || true)"
  fi
fi
if [[ -n "${JAVA11_HOME:-}" ]]; then
  export JAVA_HOME="${JAVA_HOME:-$JAVA11_HOME}"
fi
export CASSANDRA_USE_JDK11="${CASSANDRA_USE_JDK11:-true}"
echo "Running :cassandra-jar (this can take several minutes)..." >&2
cd "$ROOT"
# Skip S3 Minio test fixture (elasticsearch.test.fixtures + JDK 11 + Gradle 5.4); not needed for the Ant jar.
./gradlew :cassandra-jar -Delassandra.skipS3TestFixture=true --no-daemon >&2
echo "$(cd "$(dirname "$JAR")" && pwd)/$(basename "$JAR")"
