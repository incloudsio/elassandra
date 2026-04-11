#!/usr/bin/env bash
# LuceneTestCase sets @ThreadLeakZombies(IGNORE_REMAINING_TESTS); the annotation is @Inherited.
# Embedded Cassandra leaves long-lived threads; leak handling can set RandomizedRunner's static
# zombieMarker, and the next test method hits checkZombies() → AssumptionViolatedException / worker exit 100.
# OpenSearchTestCase is the base for org.opensearch.test.*; override to CONTINUE for the whole tree.
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
F="$DEST/test/framework/src/main/java/org/opensearch/test/OpenSearchTestCase.java"
[[ -f "$F" ]] || exit 0

if grep -q '@ThreadLeakZombies' "$F" 2>/dev/null; then
  echo "OpenSearchTestCase already has @ThreadLeakZombies → $F"
  exit 0
fi

python3 - "$F" <<'PY'
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
if "@ThreadLeakZombies" in text:
    sys.exit(0)
imp = "import com.carrotsearch.randomizedtesting.annotations.ThreadLeakScope.Scope;\n"
if imp not in text:
    print("OpenSearchTestCase: expected ThreadLeakScope.Scope import not found →", path, file=sys.stderr)
    sys.exit(1)
text = text.replace(
    imp,
    imp
    + "import com.carrotsearch.randomizedtesting.annotations.ThreadLeakZombies;\n"
    + "import com.carrotsearch.randomizedtesting.annotations.ThreadLeakZombies.Consequence;\n",
    1,
)
marker = "@ThreadLeakScope(Scope.SUITE)\n"
if marker not in text:
    print("OpenSearchTestCase: expected @ThreadLeakScope(SUITE) not found →", path, file=sys.stderr)
    sys.exit(1)
text = text.replace(
    marker,
    marker + "@ThreadLeakZombies(Consequence.CONTINUE)\n",
    1,
)
path.write_text(text, encoding="utf-8")
print("Patched OpenSearchTestCase (@ThreadLeakZombies(CONTINUE)) →", path)
PY
