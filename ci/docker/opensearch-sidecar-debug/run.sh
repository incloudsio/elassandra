#!/usr/bin/env bash
# Run OpenSearch side-car Gradle workflows in Linux (repro native/JNI issues seen on macOS).
#
# Prerequisites on the host:
#   - This Elassandra repo checkout
#   - A git clone of OpenSearch 1.3.x (default: ../incloudsio-opensearch next to the repo)
#   - Optional: pre-built Cassandra jar at server/cassandra/build/elassandra-cassandra-*.jar
#      (otherwise build-elassandra-cassandra-jar.sh runs inside the container — slow)
#
# Usage:
#   ./ci/docker/opensearch-sidecar-debug/run.sh
#   ./ci/docker/opensearch-sidecar-debug/run.sh ./scripts/opensearch-sidecar-compile-try.sh
#   OPENSEARCH_CLONE_DIR=/path/to/OpenSearch ./ci/docker/opensearch-sidecar-debug/run.sh ./scripts/opensearch-sidecar-test-try.sh
#   ./ci/docker/opensearch-sidecar-debug/run.sh shell
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
IMAGE="${IMAGE:-elassandra-opensearch-sidecar-debug:latest}"

OPS="${OPENSEARCH_CLONE_DIR:-$REPO_ROOT/../incloudsio-opensearch}"
if [[ ! -d "$OPS/.git" ]]; then
  echo "OpenSearch clone not found at: $OPS" >&2
  echo "Clone 1.3.x (e.g. ./scripts/clone-opensearch-upstream.sh) or set OPENSEARCH_CLONE_DIR." >&2
  exit 1
fi
OPS_ABS="$(cd "$OPS" && pwd)"

docker build -t "$IMAGE" "$SCRIPT_DIR"

MEM="${DOCKER_MEMORY:-8g}"

# OpenSearch tests call Bootstrap.initializeNatives(), which throws if the JVM runs as root
# (default uid in Docker). Run as the invoking host user so bind mounts stay writable, or set DOCKER_USER.
DOCKER_USER_ARGS=()
if [[ -n "${DOCKER_USER:-}" ]]; then
  DOCKER_USER_ARGS=(--user "$DOCKER_USER")
elif command -v id >/dev/null 2>&1; then
  _uid="$(id -u)"
  if [[ "$_uid" != "0" ]]; then
    DOCKER_USER_ARGS=(--user "${_uid}:$(id -g)")
  else
    echo "Docker runs as root by default; OpenSearch tests require a non-root uid. Using --user 1000:1000 (override with DOCKER_USER)." >&2
    DOCKER_USER_ARGS=(--user 1000:1000)
  fi
fi

# Use -it only when attached to a terminal (avoids "input device is not a TTY" in CI / scripts).
DOCKER_TTY=()
if [[ "${DOCKER_FORCE_TTY:-}" == "1" ]] || { [[ -t 0 ]] && [[ -t 1 ]]; }; then
  DOCKER_TTY=(-it)
else
  DOCKER_TTY=(-i)
fi
RUN_ARGS=(docker run --rm "${DOCKER_TTY[@]}" "${DOCKER_USER_ARGS[@]}" --memory="$MEM"
  -v "$REPO_ROOT:/workspace/elassandra:rw"
  -v "$OPS_ABS:/workspace/opensearch:rw"
  -w /workspace/elassandra
  -e OPENSEARCH_CLONE_DIR=/workspace/opensearch
)

if [[ "${1:-}" == "shell" ]]; then
  "${RUN_ARGS[@]}" "$IMAGE" bash -l
  exit 0
fi

DEFAULT=(./scripts/opensearch-sidecar-compile-try.sh)
if [[ $# -gt 0 ]]; then
  CMD=("$@")
else
  CMD=("${DEFAULT[@]}")
fi

"${RUN_ARGS[@]}" "$IMAGE" \
  bash -c 'export RUNTIME_JAVA_HOME="${RUNTIME_JAVA_HOME:-$JAVA_HOME}"; cd /workspace/elassandra && exec "$@"' _ "${CMD[@]}"
