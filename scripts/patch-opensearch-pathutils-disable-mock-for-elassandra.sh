#!/usr/bin/env bash
# PathUtilsForTesting.setup() installs Lucene's mock FS; combined with OpenSearch's java.io.tmpdir=workingDir/temp
# and embedded Cassandra, workers hit FileAlreadyExistsException and exit 100. Elassandra sets
# -Delassandra.disable.lucene.mock.filesystem=true (init.gradle) to keep the real default FS when this patch is applied.
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
F="$DEST/test/framework/src/main/java/org/opensearch/common/io/PathUtilsForTesting.java"
[[ -f "$F" ]] || exit 0

if grep -q 'elassandra.disable.lucene.mock.filesystem' "$F" 2>/dev/null; then
  echo "PathUtilsForTesting Elassandra mock skip already present → $F"
  exit 0
fi

python3 - "$F" <<'PY'
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
old = """    public static void setup() {
        installMock(LuceneTestCase.createTempDir().getFileSystem());
    }"""
new = """    public static void setup() {
        // Elassandra embedded Cassandra + OpenSearch: Lucene's mock FS fights java.io.tmpdir / Gradle working-dir
        // layout (FileAlreadyExistsException on createDirectory, worker exit 100). Use the real default FS.
        if (Boolean.parseBoolean(System.getProperty("elassandra.disable.lucene.mock.filesystem", "false"))) {
            PathUtils.DEFAULT = PathUtils.ACTUAL_DEFAULT;
            return;
        }
        installMock(LuceneTestCase.createTempDir().getFileSystem());
    }"""
if old not in text:
    print("PathUtilsForTesting: expected setup() body not found; skip →", path, file=sys.stderr)
    sys.exit(0)
path.write_text(text.replace(old, new, 1), encoding="utf-8")
print("Patched PathUtilsForTesting (Elassandra optional real FS) →", path)
PY
