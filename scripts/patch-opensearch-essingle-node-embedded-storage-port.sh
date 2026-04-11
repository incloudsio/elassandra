#!/usr/bin/env bash
# Idempotent: embedded Config supplier may exist without c.storage_port (config-override.sh skips once "data_file_directories" appears).
# Default 17100 avoids clashing with a system Cassandra on 7000; forked JVM gets -Delassandra.test.storage_port from opensearch-sidecar-test-try.sh + init.gradle.
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
F="$DEST/test/framework/src/main/java/org/opensearch/test/OpenSearchSingleNodeTestCase.java"
[[ -f "$F" ]] || exit 0

python3 - "$F" <<'PY'
import pathlib, re, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
if re.search(r"^\s*c\.storage_port\s*=\s*Integer\.getInteger\(\s*\"elassandra\.test\.storage_port\"", text, re.M):
    print("OpenSearchSingleNodeTestCase: embedded storage_port already set →", path)
    sys.exit(0)
needle = 'c.hints_directory = new java.io.File(home, "hints").getPath();'
if needle not in text:
    print("OpenSearchSingleNodeTestCase: hints_directory anchor missing →", path, file=sys.stderr)
    sys.exit(0)
insert = needle + "\n                    c.storage_port = Integer.getInteger(\"elassandra.test.storage_port\", 17100);"
text = text.replace(needle, insert, 1)
path.write_text(text, encoding="utf-8")
print("Patched embedded c.storage_port →", path)
PY
