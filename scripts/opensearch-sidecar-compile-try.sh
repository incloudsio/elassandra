#!/usr/bin/env bash
# Sync org.elassandra.* into the OpenSearch side-car, rewrite imports, attach Elassandra Cassandra jar, run :server:compileJava.
# Remaining errors usually mean fork-only org.opensearch types (e.g. CqlMapper) are not merged yet.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${OPENSEARCH_CLONE_DIR:-$ROOT/../opensearch-upstream}"
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

"$ROOT/scripts/sync-elassandra-to-opensearch-sidecar.sh"
"$ROOT/scripts/sync-elassandra-fork-minimal-to-opensearch-sidecar.sh" "$DEST"
"$ROOT/scripts/sync-elassandra-fork-overlay-to-opensearch-sidecar.sh" "$DEST"
"$ROOT/scripts/sync-elassandra-routing-overlay-to-opensearch-sidecar.sh" "$DEST"
"$ROOT/scripts/rewrite-elassandra-imports-for-opensearch.sh" "$DEST"
"$ROOT/scripts/patch-opensearch-sourcetoparse-elassandra-token.sh" "$DEST"
"$ROOT/scripts/patch-opensearch-fieldmapper-elassandra-createfield.sh" "$DEST"
"$ROOT/scripts/patch-opensearch-elassandra-sidecar-templates.sh" "$DEST"
"$ROOT/scripts/patch-opensearch-metadata-elassandra-extensions.sh" "$DEST"
"$ROOT/scripts/patch-opensearch-cluster-service-elassandra-stubs.sh" "$DEST"
"$ROOT/scripts/patch-opensearch-cluster-service-elassandra-schema-stubs.sh" "$DEST"
"$ROOT/scripts/patch-opensearch-mappers-elassandra-cql-compat.sh" "$DEST"
"$ROOT/scripts/overlay-elassandra-parsecontext-to-opensearch-sidecar.sh" "$DEST"
"$ROOT/scripts/install-elassandra-cluster-changed-event-opensearch.sh" "$DEST"
"$ROOT/scripts/patch-opensearch-master-service-taskinputs-public.sh" "$DEST"
"$ROOT/scripts/patch-org-elassandra-opensearch-no-schema-update.sh" "$DEST"
"$ROOT/scripts/patch-org-elassandra-opensearch-elastic-secondary.sh" "$DEST"
"$ROOT/scripts/patch-opensearch-engine-delete-by-query.sh" "$DEST"
"$ROOT/scripts/patch-cassandra-discovery-for-opensearch.sh" "$DEST"
if [[ "${SKIP_OPENSEARCH_FORBIDDEN_DEPS_PATCH:-}" != "1" ]]; then
  "$ROOT/scripts/patch-opensearch-forbidden-deps-for-elassandra.sh" "$DEST"
fi
cd "$DEST"
# OpenSearch's gradlew often does not forward CLI -D to the build JVM; use GRADLE_OPTS (see gradle/opensearch-sidecar-elassandra.init.gradle).
export GRADLE_OPTS="${GRADLE_OPTS:-} -Delassandra.cassandra.jar=$JAR"
exec ./gradlew -I "$INIT_GRADLE" :server:compileJava --no-daemon "$@"
