#!/usr/bin/env bash
# Elassandra Gradle requires JAVA11_HOME (see buildSrc BuildPlugin.groovy findCompilerJavaHome).
# Plain ./gradlew :cassandra-jar fails with "JAVA_HOME must be set" if only java is on PATH.
# Usage: ./scripts/gradlew-with-jdk11.sh :cassandra-jar
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ -z "${JAVA11_HOME:-}" ]] && [[ -n "${JAVA_HOME:-}" ]] && [[ -d "${JAVA_HOME}" ]]; then
  export JAVA11_HOME="$JAVA_HOME"
fi
if [[ -z "${JAVA11_HOME:-}" ]] && command -v /usr/libexec/java_home >/dev/null 2>&1; then
  export JAVA11_HOME="$(/usr/libexec/java_home -v 11 2>/dev/null || true)"
fi
if [[ -z "${JAVA11_HOME:-}" ]] && command -v java >/dev/null 2>&1; then
  _jh="$(java -XshowSettings:properties -version 2>&1 | sed -n 's/.*java\.home = //p' | tr -d '\r')"
  if [[ -n "$_jh" ]] && [[ -d "$_jh" ]]; then
    export JAVA_HOME="${JAVA_HOME:-$_jh}"
    export JAVA11_HOME="$JAVA_HOME"
  fi
fi
if [[ -z "${JAVA11_HOME:-}" ]]; then
  echo "Could not resolve JAVA11_HOME. Set it to JDK 11, e.g.:" >&2
  echo "  export JAVA11_HOME=\"\$(/usr/libexec/java_home -v 11)\"" >&2
  exit 1
fi
export JAVA_HOME="${JAVA_HOME:-$JAVA11_HOME}"
export JAVA12_HOME="${JAVA12_HOME:-$JAVA11_HOME}"

# Gradle daemon keeps the environment from its first start; a daemon launched without JAVA11_HOME
# will still see getenv("JAVA11_HOME") == null. Stop daemons so this shell's exports apply.
"$ROOT/gradlew" --stop 2>/dev/null || true

exec "$ROOT/gradlew" "$@"
