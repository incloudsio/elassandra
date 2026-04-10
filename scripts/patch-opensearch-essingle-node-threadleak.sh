#!/usr/bin/env bash
# Cassandra + Netty leave long-lived threads; OpenSearchTestCase uses @ThreadLeakScope(SUITE) by default.
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
F="$DEST/test/framework/src/main/java/org/opensearch/test/OpenSearchSingleNodeTestCase.java"
[[ -f "$F" ]] || exit 0

if grep -q '@ThreadLeakScope' "$F" 2>/dev/null; then
  echo "OpenSearchSingleNodeTestCase already has @ThreadLeakScope → $F"
  exit 0
fi

python3 - "$F" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
if "@ThreadLeakScope" in text:
    sys.exit(0)
# Insert imports after package line
if "import com.carrotsearch.randomizedtesting.annotations.ThreadLeakScope" not in text:
    text = text.replace(
        "import com.carrotsearch.randomizedtesting.RandomizedContext;",
        """import com.carrotsearch.randomizedtesting.annotations.ThreadLeakScope;
import com.carrotsearch.randomizedtesting.annotations.ThreadLeakScope.Scope;
import com.carrotsearch.randomizedtesting.RandomizedContext;""",
        1,
    )
marker = "public abstract class OpenSearchSingleNodeTestCase extends OpenSearchTestCase {"
if marker not in text:
    print("Could not find OpenSearchSingleNodeTestCase class declaration", file=sys.stderr)
    sys.exit(1)
text = text.replace(
    marker,
    "@ThreadLeakScope(Scope.NONE)\n" + marker,
    1,
)
path.write_text(text, encoding="utf-8")
print("Patched @ThreadLeakScope(NONE) on OpenSearchSingleNodeTestCase →", path)
PY
