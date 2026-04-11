#!/usr/bin/env bash
# Build a discardable javaagent that prints exit code + stack when System.exit runs (works with tests.security.manager=false).
# Output: /tmp/elassandra-system-exit-trace-agent.jar (not committed).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT/.tmp-exit-agent-build"
ASM_VER="9.6"
ASM_JAR="$BUILD_DIR/asm-${ASM_VER}.jar"
SRC="$ROOT/scripts/exit-trace-javaagent/ExitTraceAgent.java"
OUT_JAR="/tmp/elassandra-system-exit-trace-agent.jar"

mkdir -p "$BUILD_DIR"
if [[ ! -f "$ASM_JAR" ]]; then
  curl -fsSL -o "$ASM_JAR" "https://repo1.maven.org/maven2/org/ow2/asm/asm/${ASM_VER}/asm-${ASM_VER}.jar"
fi
TMPCLS="$BUILD_DIR/classes"
rm -rf "$TMPCLS"
mkdir -p "$TMPCLS"
# shellcheck disable=SC2207
JAVA_HOME="${JAVA_HOME:-$(/usr/libexec/java_home -v 11 2>/dev/null || /usr/libexec/java_home 2>/dev/null || true)}"
if [[ -z "${JAVA_HOME:-}" ]]; then
  echo "Set JAVA_HOME to JDK 11+." >&2
  exit 1
fi
"$JAVA_HOME/bin/javac" --release 11 -cp "$ASM_JAR" -d "$TMPCLS" "$SRC"
# Premain loads ASM at runtime — bundle it (the agent JAR is not on a classpath with ASM otherwise).
unzip -qo "$ASM_JAR" -d "$TMPCLS"

TMPMAN="$BUILD_DIR/MANIFEST.MF"
cat >"$TMPMAN" <<EOF
Premain-Class: elassandra.debug.ExitTraceAgent
Can-Retransform-Classes: true

EOF

"$JAVA_HOME/bin/jar" --create --file "$OUT_JAR" --manifest "$TMPMAN" -C "$TMPCLS" .
echo "Built $OUT_JAR"
