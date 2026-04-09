#!/usr/bin/env bash
# After opensearch-sidecar-prepare.sh, run :server:test for Elassandra tests in the OpenSearch side-car.
#
# Almost all org.elassandra.* tests extend ESSingleNodeTestCase and need a real Cassandra + Elassandra
# bootstrap (not the compile stub). Use a machine with cassandra.home configured or expect failures
# until ElassandraDaemon is fully ported to OpenSearch.
#
# Usage:
#   JAVA_HOME=/path/to/jdk-11 ./scripts/opensearch-sidecar-test-try.sh
# Narrow pattern (Gradle --tests):
#   OPENSEARCH_SIDECAR_TEST_PATTERN='org.elassandra.PendingClusterStateTests' ./scripts/opensearch-sidecar-test-try.sh
#
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${OPENSEARCH_CLONE_DIR:-$ROOT/../incloudsio-opensearch}"
INIT_GRADLE="$ROOT/gradle/opensearch-sidecar-elassandra.init.gradle"

if [[ -z "${JAVA_HOME:-}" ]]; then
  echo "Set JAVA_HOME to JDK 11+ (OpenSearch 1.3 requirement)." >&2
  exit 1
fi

# OpenSearch's :server:test normally downloads a "bundled" JDK for the test JVM unless a runtime JDK is
# explicitly set (see upstream gradle/runtime-jdk-provision.gradle). Point it at the same JDK as the build
# so Apple Silicon / offline CI does not fail resolving adoptium_11 artifacts.
export RUNTIME_JAVA_HOME="${RUNTIME_JAVA_HOME:-$JAVA_HOME}"

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
export GRADLE_OPTS="${GRADLE_OPTS:-} -Delassandra.cassandra.jar=$JAR"

# Default Cassandra layout for ESSingleNodeTestCase (YamlConfigurationLoader needs a file: URI for cassandra.config).
# Prefer distribution/src (Cassandra 4.x-shaped yaml shipped for packages) over the slimmer server test fixture.
# Override with ELASSANDRA_TEST_CASSANDRA_HOME or skip with SKIP_ELASSANDRA_TEST_CASSANDRA_SYS_PROPS=1.
if [[ -n "${ELASSANDRA_TEST_CASSANDRA_HOME:-}" ]]; then
  CASS_TEST_ROOT="$ELASSANDRA_TEST_CASSANDRA_HOME"
elif [[ -f "$ROOT/distribution/src/conf/cassandra.yaml" ]]; then
  CASS_TEST_ROOT="$ROOT/distribution/src"
else
  CASS_TEST_ROOT="$ROOT/server/src/test/resources"
fi
if [[ -f "$CASS_TEST_ROOT/conf/cassandra.yaml" ]] && [[ "${SKIP_ELASSANDRA_TEST_CASSANDRA_SYS_PROPS:-}" != "1" ]]; then
  _ABS="$(cd "$CASS_TEST_ROOT" && pwd)"
  export GRADLE_OPTS="${GRADLE_OPTS} -Dcassandra.home=${_ABS} -Dcassandra.config=file://${_ABS}/conf/cassandra.yaml"
fi

# Default: one test class as smoke; set to org.elassandra.* for full package (slow, needs runtime).
PATTERN="${OPENSEARCH_SIDECAR_TEST_PATTERN:-org.elassandra.ClusterSettingsTests}"

exec ./gradlew -I "$INIT_GRADLE" :server:test --tests "$PATTERN" -Dtests.security.manager=false --no-daemon "$@"
