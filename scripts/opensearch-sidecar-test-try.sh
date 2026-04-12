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
# Single test method (fastest iteration — one method, not the whole class):
#   OPENSEARCH_SIDECAR_TEST_PATTERN='org.elassandra.ClusterSettingsTests.testIndexBadSearchStrategy' ./scripts/opensearch-sidecar-test-try.sh
# Same from the OpenSearch clone (after prepare); omit :server:cleanTest while iterating to save minutes per run:
#   OPENSEARCH_SIDECAR_SKIP_CLEAN_TEST=1 OPENSEARCH_SIDECAR_TEST_PATTERN='org.elassandra.FooTests.barMethod' ./scripts/opensearch-sidecar-test-try.sh
# Or call Gradle directly (still needs -I init.gradle + cassandra -D… from GRADLE_OPTS / env):
#   cd "$OPENSEARCH_CLONE_DIR" && ./gradlew -I "$ELASSANDRA_ROOT/gradle/opensearch-sidecar-elassandra.init.gradle" \
#     :server:test --tests 'org.elassandra.ClusterSettingsTests.testIndexBadSearchStrategy' -Dtests.jvms=1 --no-daemon
# Curated waves (overrides OPENSEARCH_SIDECAR_TEST_PATTERN when set):
#   OPENSEARCH_SIDECAR_TEST_WAVE=0|1|2|3|4 ./scripts/opensearch-sidecar-test-try.sh
# Suite timeout (randomizedtesting default is 20m — long when debugging hangs). Shorter default here; restore 20m with:
#   OPENSEARCH_SIDECAR_SUITE_TIMEOUT_MS=1200000 ./scripts/opensearch-sidecar-test-try.sh
#   OPENSEARCH_SIDECAR_SUITE_TIMEOUT_MS=0 disables this script’s -D (use Gradle/OpenSearch defaults).
# Fast-fail when debugging stuck gateway/ring (seconds + minutes; default barrier 600s, master wait 5m):
#   GRADLE_OPTS='-Delassandra.test.shard.barrier.wait.seconds=30 -Delassandra.test.master.wait.minutes=1' ./scripts/opensearch-sidecar-test-try.sh
# Extra JVM args for forked test workers (passed through init.gradle):
#   ELASSANDRA_OPENSEARCH_TEST_EXTRA_JVM_ARGS='-Xmx2g' ./scripts/opensearch-sidecar-test-try.sh
# Debug opaque worker exit 100: enables shutdown hook + default uncaught handler in ESSingleNodeTestCase static init.
#   ELASSANDRA_TEST_SHUTDOWN_HOOK=1 ./scripts/opensearch-sidecar-test-try.sh
# Log stack traces for System.exit (needs tests.security.manager=false — side-car default):
#   ELASSANDRA_TEST_TRACE_SYSTEM_EXIT=1 ./scripts/opensearch-sidecar-test-try.sh
# When SM is off, checkExit never runs — use a discardable javaagent that retransforms java.lang.System#exit:
#   ./scripts/build-exit-trace-javaagent.sh
#   ELASSANDRA_OPENSEARCH_TEST_EXTRA_JVM_ARGS='-javaagent:/tmp/elassandra-system-exit-trace-agent.jar' OPENSEARCH_SIDECAR_TESTS_JVMS=1 ./scripts/opensearch-sidecar-test-try.sh
# Parallel test JVMs: OpenSearch defaults tests.jvms to CPU count; embedded Cassandra uses one storage_port
# (17100) per machine — multiple forks bind the same port and fail. This script defaults OPENSEARCH_SIDECAR_TESTS_JVMS=1;
# set OPENSEARCH_SIDECAR_TESTS_JVMS=N only if you assign distinct ports per fork (not supported here).
#
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${OPENSEARCH_CLONE_DIR:-$ROOT/../incloudsio-opensearch}"
INIT_GRADLE="$ROOT/gradle/opensearch-sidecar-elassandra.init.gradle"

if [[ -z "${JAVA_HOME:-}" ]]; then
  echo "Set JAVA_HOME to JDK 11+ (OpenSearch 1.3 requirement)." >&2
  exit 1
fi
# Elassandra BuildPlugin.findCompilerJavaHome() uses JAVA11_HOME (message text still says JAVA_HOME).
export JAVA11_HOME="${JAVA11_HOME:-$JAVA_HOME}"
export JAVA12_HOME="${JAVA12_HOME:-$JAVA_HOME}"

# OpenSearch's :server:test normally downloads a "bundled" JDK for the test JVM unless a runtime JDK is
# explicitly set (see upstream gradle/runtime-jdk-provision.gradle). Point it at the same JDK as the build
# so Apple Silicon / offline CI does not fail resolving adoptium_11 artifacts.
export RUNTIME_JAVA_HOME="${RUNTIME_JAVA_HOME:-$JAVA_HOME}"

# See header: one test JVM avoids storage_port / embedded singleton contention across forks.
OPENSEARCH_SIDECAR_TESTS_JVMS="${OPENSEARCH_SIDECAR_TESTS_JVMS:-1}"

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
  # Fresh Cassandra data dirs for each side-car run (stale system keyspace / commitlog breaks init and triggers
  # JVMStabilityInspector → System.exit(100)).
  rm -rf "${_ABS}/data" "${_ABS}/commitlog" "${_ABS}/saved_caches" "${_ABS}/hints" 2>/dev/null || true
  mkdir -p "${_ABS}/data" "${_ABS}/data/hints" "${_ABS}/commitlog" "${_ABS}/saved_caches" "${_ABS}/hints" 2>/dev/null || true
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

# Embedded Cassandra storage_port; default 17100 avoids conflict with a system Cassandra on 7000.
ELASSANDRA_TEST_STORAGE_PORT="${ELASSANDRA_TEST_STORAGE_PORT:-17100}"
export GRADLE_OPTS="${GRADLE_OPTS} -Delassandra.test.storage_port=${ELASSANDRA_TEST_STORAGE_PORT}"

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
CLASS_LIST=()
IFS=',' read -ra _PAT_ARR <<< "$PATTERN"
for _c in "${_PAT_ARR[@]}"; do
  _t="${_c#"${_c%%[![:space:]]*}"}"
  _t="${_t%"${_t##*[![:space:]]}"}"
  [[ -z "$_t" ]] && continue
  CLASS_LIST+=("$_t")
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
GRADLE_EXTRA_D+=("-Dtests.jvms=${OPENSEARCH_SIDECAR_TESTS_JVMS}")
GRADLE_EXTRA_D+=("-Delassandra.test.storage_port=${ELASSANDRA_TEST_STORAGE_PORT:-17100}")
# RandomizedTesting suite timeout (ms); "!" forces override of @TimeoutSuite. Default 5m unless disabled via 0.
_OPENSEARCH_SUITE_TO="${OPENSEARCH_SIDECAR_SUITE_TIMEOUT_MS:-300000}"
if [[ "${_OPENSEARCH_SUITE_TO}" != "0" ]]; then
  GRADLE_EXTRA_D+=("-Dtests.timeoutSuite=${_OPENSEARCH_SUITE_TO}!")
fi

# Default: :server:cleanTest before :server:test so stale JUnit XML does not mask failures. While iterating on one
# method, set OPENSEARCH_SIDECAR_SKIP_CLEAN_TEST=1 to skip clean and shorten each round (still compiles if sources changed).
# (Do not use an empty bash array with set -u — "${_CLEAN[@]}" is "unbound" when _CLEAN=().)
#
# Waves 1–3 list multiple test classes; the embedded Elassandra/OpenSearch singleton in one JVM often breaks between
# classes (cluster blocks, master discovery). Run one Gradle :server:test per class unless
# OPENSEARCH_SIDECAR_BATCH_TEST_CLASSES=1 (old single-invocation behavior). Wave 4 uses org.elassandra.* — keep one run.
set +e
_gradle_rc=0
GRADLE_CMD=(./gradlew "${GRADLE_EXTRA_D[@]}" -I "$INIT_GRADLE")
if [[ "${OPENSEARCH_SIDECAR_SKIP_CLEAN_TEST:-}" != "1" ]]; then
  GRADLE_CMD+=(:server:cleanTest)
fi
if [[ "${OPENSEARCH_SIDECAR_BATCH_TEST_CLASSES:-}" != "1" ]] && [[ "${OPENSEARCH_SIDECAR_TEST_WAVE:-}" =~ ^[123]$ ]] && [[ ${#CLASS_LIST[@]} -gt 1 ]]; then
  for _cls in "${CLASS_LIST[@]}"; do
    "${GRADLE_CMD[@]}" :server:test --tests "$_cls" --no-daemon "$@" || _gradle_rc=$?
    if [[ "$_gradle_rc" -ne 0 ]]; then
      break
    fi
    sleep 1
  done
else
  "${GRADLE_CMD[@]}" :server:test "${TEST_ARGS[@]}" --no-daemon "$@" || _gradle_rc=$?
fi
set -e
if [[ "$_gradle_rc" -ne 0 ]]; then
  echo "opensearch-sidecar-test-try: :server:test failed (exit $_gradle_rc)." >&2
  exit "$_gradle_rc"
fi
exit 0
