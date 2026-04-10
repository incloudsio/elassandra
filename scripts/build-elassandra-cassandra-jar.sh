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
# elasticsearch.build checks System.getenv("JAVA_HOME"), not only java.home. On Linux CI, JDK is often
# on PATH while JAVA_HOME is unset (or empty if a workflow expression failed); derive from the JVM.
if [[ -z "${JAVA_HOME:-}" ]] || [[ ! -d "${JAVA_HOME}" ]]; then
  if command -v java >/dev/null 2>&1; then
    _jh="$(java -XshowSettings:properties -version 2>&1 | sed -n 's/.*java\.home = //p' | tr -d '\r')"
    if [[ -n "$_jh" ]] && [[ -d "$_jh" ]]; then
      export JAVA_HOME="$_jh"
    fi
  fi
fi
export CASSANDRA_USE_JDK11="${CASSANDRA_USE_JDK11:-true}"
echo "Running :cassandra-jar (this can take several minutes)..." >&2
cd "$ROOT"
# Minio fixture is skipped by default in plugins/repository-s3; explicit flag keeps behaviour if defaults change.
./gradlew :cassandra-jar -Delassandra.skipS3TestFixture=true --no-daemon >&2
echo "$(cd "$(dirname "$JAR")" && pwd)/$(basename "$JAR")"
