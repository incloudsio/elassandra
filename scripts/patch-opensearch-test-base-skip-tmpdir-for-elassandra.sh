#!/usr/bin/env bash
# Elassandra init.gradle sets a unique java.io.tmpdir in Test#doFirst; skip OpenSearch's workingDir/temp override when
# elassandra.gradle.skip.test.tmpdir=true (set by init script before projects load).
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
F="$DEST/buildSrc/src/main/java/org/opensearch/gradle/OpenSearchTestBasePlugin.java"
[[ -f "$F" ]] || exit 0

if grep -q 'elassandra.gradle.skip.test.tmpdir' "$F" 2>/dev/null; then
  echo "OpenSearchTestBasePlugin tmpdir skip for Elassandra already present → $F"
  exit 0
fi

python3 - "$F" <<'PY'
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
old = '            nonInputProperties.systemProperty("java.io.tmpdir", test.getWorkingDir().toPath().resolve("temp"));'
new = """            // Elassandra init.gradle sets elassandra.gradle.skip.test.tmpdir and supplies java.io.tmpdir in Test#doFirst.
            if (Boolean.parseBoolean(System.getProperty("elassandra.gradle.skip.test.tmpdir", "false")) == false) {
                nonInputProperties.systemProperty("java.io.tmpdir", test.getWorkingDir().toPath().resolve("temp"));
            }"""
if old not in text:
    print("OpenSearchTestBasePlugin: expected java.io.tmpdir line not found; skip →", path, file=sys.stderr)
    sys.exit(0)
path.write_text(text.replace(old, new, 1), encoding="utf-8")
print("Patched OpenSearchTestBasePlugin (optional skip tmpdir) →", path)
PY
