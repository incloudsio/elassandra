#!/usr/bin/env bash
# OpenSearchTestBasePlugin.doFirst used to mkdir(workingDir) before any init.gradle doFirst could delete stale
# build/testrun; a second doFirst then deleted testrun *after* mkdirs, leaving inconsistent state. Lucene's mock FS
# then hits FileAlreadyExistsException on createDirectory(temp) → SKIPPED + worker exit 100.
# Fix: delete build/testrun at the *start* of the same doFirst, before mkdirs(testOutputDir/heapdump/workingDir).
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
F="$DEST/buildSrc/src/main/java/org/opensearch/gradle/OpenSearchTestBasePlugin.java"
[[ -f "$F" ]] || exit 0

if grep -q 'Delete stale testrun before mkdirs' "$F" 2>/dev/null; then
  echo "OpenSearchTestBasePlugin delete testrun before mkdir already patched → $F"
  exit 0
fi

python3 - "$F" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
old = """                @Override
                public void execute(Task t) {
                    mkdirs(testOutputDir);
                    mkdirs(heapdumpDir);
                    mkdirs(test.getWorkingDir());
                    // Do not mkdir workingDir/temp: Lucene PathUtilsForTesting installs a mock FS and expects to create
"""
new = """                @Override
                public void execute(Task t) {
                    // Delete stale testrun before mkdirs(workingDir). A separate init.gradle doFirst that ran *after* this
                    // block used to delete testrun too late, leaving java.io.tmpdir paths from prior runs and causing
                    // FileAlreadyExistsException on createDirectory(temp) → SKIPPED tests and Gradle worker exit 100.
                    File testrunRoot = new File(project.getBuildDir(), "testrun");
                    if (testrunRoot.exists()) {
                        project.delete(testrunRoot);
                    }
                    mkdirs(testOutputDir);
                    mkdirs(heapdumpDir);
                    mkdirs(test.getWorkingDir());
                    // Do not mkdir workingDir/temp: Lucene PathUtilsForTesting installs a mock FS and expects to create
"""
if old not in text:
    print("patch-opensearch-test-base-delete-testrun-before-mkdir: expected doFirst anchor not found →", path, file=sys.stderr)
    sys.exit(1)
path.write_text(text.replace(old, new, 1), encoding="utf-8")
print("Patched OpenSearchTestBasePlugin (delete testrun before mkdir) →", path)
PY
