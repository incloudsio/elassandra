#!/usr/bin/env bash
# After opensearch-sidecar-prepare.sh, run :server:test for Elassandra tests in the OpenSearch side-car.
#
# Almost all org.elassandra.* tests extend ESSingleNodeTestCase and need a real Cassandra + Elassandra
# bootstrap (not the compile stub). Use a machine with cassandra.home configured or expect failures
# until ElassandraDaemon is fully ported to OpenSearch.
#
# Usage:
#   JAVA_HOME=/path/to/jdk-11 ./scripts/opensearch-sidecar-test-try.sh
# Narrow pattern (Gradle --tests); comma-separated runs multiple classes:
#   OPENSEARCH_SIDECAR_TEST_PATTERN='org.elassandra.PendingClusterStateTests,org.elassandra.NamingTests' ./scripts/opensearch-sidecar-test-try.sh
# Curated waves (overrides OPENSEARCH_SIDECAR_TEST_PATTERN when set):
#   OPENSEARCH_SIDECAR_TEST_WAVE=0|1|2|3|4 ./scripts/opensearch-sidecar-test-try.sh
# Extra JVM args for forked test workers (passed through init.gradle):
#   ELASSANDRA_OPENSEARCH_TEST_EXTRA_JVM_ARGS='-Xmx2g' ./scripts/opensearch-sidecar-test-try.sh
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
# Lucene PathUtilsForTesting + mock FS: stale server/build/testrun/test/temp from a prior run can make createDirectory fail with FileAlreadyExistsException (suite SKIPPED, Gradle worker exit 100). :cleanTest does not remove this tree.
rm -rf "$DEST/server/build/testrun" 2>/dev/null || true
export GRADLE_OPTS="${GRADLE_OPTS:-} -Delassandra.cassandra.jar=$JAR"

# Default Cassandra layout for ESSingleNodeTestCase (YamlConfigurationLoader needs a file: URI for cassandra.config).
# Prefer server/src/test/resources (minimal yaml known to load with the Elassandra Cassandra jar in :server:test).
# Use ELASSANDRA_TEST_CASSANDRA_HOME=distribution/src only when validating package-shaped config.
# Override with ELASSANDRA_TEST_CASSANDRA_HOME or skip with SKIP_ELASSANDRA_TEST_CASSANDRA_SYS_PROPS=1.
if [[ -n "${ELASSANDRA_TEST_CASSANDRA_HOME:-}" ]]; then
  CASS_TEST_ROOT="$ELASSANDRA_TEST_CASSANDRA_HOME"
elif [[ -f "$ROOT/server/src/test/resources/conf/cassandra.yaml" ]]; then
  CASS_TEST_ROOT="$ROOT/server/src/test/resources"
elif [[ -f "$ROOT/distribution/src/conf/cassandra.yaml" ]]; then
  CASS_TEST_ROOT="$ROOT/distribution/src"
else
  CASS_TEST_ROOT="$ROOT/server/src/test/resources"
fi
if [[ "${SKIP_ELASSANDRA_TEST_CASSANDRA_SYS_PROPS:-}" != "1" ]]; then
  _ABS="$(cd "$CASS_TEST_ROOT" && pwd)"
  # Default dirs Cassandra uses when paths are relative to cassandra.home (embedded tests).
  mkdir -p "${_ABS}/data" "${_ABS}/data/hints" "${_ABS}/commitlog" "${_ABS}/saved_caches" "${_ABS}/hints" 2>/dev/null || true
  # Legacy: OpenSearch data used to live under cassandra data; leftover dirs are harmless. Current ESSingleNodeTestCase uses Lucene temp (mock FS).
  rm -rf "${_ABS}/data/elasticsearch.data" 2>/dev/null || true
  _CONFIG_URI=""
  if [[ -n "${ELASSANDRA_TEST_CASSANDRA_CONFIG:-}" ]]; then
    _CF="$(cd "$(dirname "${ELASSANDRA_TEST_CASSANDRA_CONFIG}")" && pwd)/$(basename "${ELASSANDRA_TEST_CASSANDRA_CONFIG}")"
    _CONFIG_URI="file://${_CF}"
  elif [[ -f "$ROOT/server/test-fixtures/cassandra-opensearch-sidecar.yaml" ]]; then
    _CF="$(cd "$ROOT/server/test-fixtures" && pwd)/cassandra-opensearch-sidecar.yaml"
    _CONFIG_URI="file://${_CF}"
  elif [[ -f "$CASS_TEST_ROOT/conf/cassandra.yaml" ]]; then
    _CONFIG_URI="file://${_ABS}/conf/cassandra.yaml"
  fi
  if [[ -n "$_CONFIG_URI" ]]; then
    export GRADLE_OPTS="${GRADLE_OPTS} -Dcassandra.home=${_ABS} -Dcassandra.config=${_CONFIG_URI}"
    # Init script also reads these if the Gradle daemon drops -D (forked workers still get props).
    export ELASSANDRA_GRADLE_CASSANDRA_HOME="${_ABS}"
    export ELASSANDRA_GRADLE_CASSANDRA_CONFIG="${_CONFIG_URI}"
  fi
fi

# Netty reads this as a boolean (true/false), not a CPU count; "1" breaks Booleans.parseBoolean in Netty4Utils.
# Default false skips pinning runtime processors (test-friendly); set to true to allow Netty to set from availableProcessors.
export OPENSEARCH_NETTY_PROCESSORS="${OPENSEARCH_NETTY_PROCESSORS:-false}"
export GRADLE_OPTS="${GRADLE_OPTS} -Dopensearch.set.netty.runtime.available.processors=${OPENSEARCH_NETTY_PROCESSORS}"

# Default: one test class as smoke; set to org.elassandra.* for full package (slow, needs runtime).
PATTERN="${OPENSEARCH_SIDECAR_TEST_PATTERN:-org.elassandra.ClusterSettingsTests}"
if [[ -n "${OPENSEARCH_SIDECAR_TEST_WAVE:-}" ]]; then
  case "$OPENSEARCH_SIDECAR_TEST_WAVE" in
    0) PATTERN="org.elassandra.ClusterSettingsTests";;
    1) PATTERN="org.elassandra.ClusterSettingsTests,org.elassandra.NamingTests,org.elassandra.TableOptionsTests";;
    2) PATTERN="org.elassandra.ClusterSettingsTests,org.elassandra.NamingTests,org.elassandra.TableOptionsTests,org.elassandra.CqlHandlerTests,org.elassandra.IndexBuildTests";;
    3) PATTERN="org.elassandra.ClusterSettingsTests,org.elassandra.NamingTests,org.elassandra.TableOptionsTests,org.elassandra.CqlHandlerTests,org.elassandra.IndexBuildTests,org.elassandra.CassandraDiscoveryTests,org.elassandra.PendingClusterStateTests,org.elassandra.SnapshotTests";;
    4) PATTERN="org.elassandra.*";;
    *)
      echo "Unknown OPENSEARCH_SIDECAR_TEST_WAVE=$OPENSEARCH_SIDECAR_TEST_WAVE (use 0-4)" >&2
      exit 1
      ;;
  esac
fi

TEST_ARGS=()
IFS=',' read -ra _PAT_ARR <<< "$PATTERN"
for _c in "${_PAT_ARR[@]}"; do
  _t="${_c#"${_c%%[![:space:]]*}"}"
  _t="${_t%"${_t##*[![:space:]]}"}"
  [[ -z "$_t" ]] && continue
  TEST_ARGS+=(--tests "$_t")
done

# Pass -D on the gradlew command line so the Gradle JVM (and init.gradle System.getProperty) always sees
# cassandra.*; GRADLE_OPTS alone is not reliably applied to the build JVM on all platforms.
GRADLE_EXTRA_D=()
if [[ "${SKIP_ELASSANDRA_TEST_CASSANDRA_SYS_PROPS:-}" != "1" ]]; then
  if [[ -n "${_ABS:-}" ]]; then
    GRADLE_EXTRA_D+=("-Dcassandra.home=${_ABS}")
  fi
  if [[ -n "${_CONFIG_URI:-}" ]]; then
    GRADLE_EXTRA_D+=("-Dcassandra.config=${_CONFIG_URI}")
  fi
fi

# Always clean test outputs so embedded Cassandra failures are not masked by stale XML (Gradle incremental test).
exec ./gradlew "${GRADLE_EXTRA_D[@]}" -I "$INIT_GRADLE" :server:cleanTest :server:test "${TEST_ARGS[@]}" -Dtests.security.manager=false --no-daemon "$@"
