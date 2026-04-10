#!/usr/bin/env bash
# Lucene PathUtilsForTesting + mock FS requires that java.io.tmpdir (workingDir/temp) not exist before the suite runs.
# OpenSearchTestBasePlugin used to mkdir that path in test.doFirst, causing FileAlreadyExistsException and SKIPPED tests.
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
F="$DEST/buildSrc/src/main/java/org/opensearch/gradle/OpenSearchTestBasePlugin.java"
[[ -f "$F" ]] || exit 0

if grep -q 'Do not mkdir workingDir/temp' "$F" 2>/dev/null; then
  echo "OpenSearchTestBasePlugin temp mkdir already patched → $F"
  exit 0
fi

if ! grep -q 'mkdirs(test.getWorkingDir().toPath().resolve("temp").toFile())' "$F" 2>/dev/null; then
  echo "OpenSearchTestBasePlugin: expected mkdir(temp) line not found; skip patch → $F" >&2
  exit 0
fi

python3 - "$F" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
old = '                    mkdirs(test.getWorkingDir().toPath().resolve("temp").toFile());\n'
if old not in text:
    print("Could not find mkdir(temp) line", file=sys.stderr)
    sys.exit(1)
new = (
    '                    // Do not mkdir workingDir/temp: Lucene PathUtilsForTesting installs a mock FS and expects to create\n'
    '                    // `temp` itself; pre-creating it causes FileAlreadyExistsException and SKIPPED tests (Elassandra side-car).\n'
)
path.write_text(text.replace(old, new, 1), encoding="utf-8")
print("Patched OpenSearchTestBasePlugin (no pre-mkdir temp) →", path)
PY
