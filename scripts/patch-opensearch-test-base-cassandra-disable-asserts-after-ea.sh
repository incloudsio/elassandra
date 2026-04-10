#!/usr/bin/env bash
# OpenSearchTestBasePlugin adds "-ea" for Lucene; Gradle may place forked-worker "-ea" after other jvmArgs.
# A trailing "-ea" re-enables assertions in org.apache.cassandra.* and embedded Cassandra can abort during setup (exit 100).
# Add "-da:org.apache.cassandra..." immediately after "-ea"/"-esa" in the same plugin block so it stays paired with asserts.
#
# Usage: ./scripts/patch-opensearch-test-base-cassandra-disable-asserts-after-ea.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
F="$DEST/buildSrc/src/main/java/org/opensearch/gradle/OpenSearchTestBasePlugin.java"
[[ -f "$F" ]] || exit 0

if grep -q 'Elassandra: -da after -ea' "$F" 2>/dev/null; then
  echo "OpenSearchTestBasePlugin Cassandra -da already patched → $F"
  exit 0
fi

python3 - "$F" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
needle = """            if (Util.getBooleanProperty("tests.asserts", true)) {
                test.jvmArgs("-ea", "-esa");
            }"""
if needle not in text:
    print("patch: tests.asserts block not found", path, file=sys.stderr)
    sys.exit(1)
repl = """            if (Util.getBooleanProperty("tests.asserts", true)) {
                test.jvmArgs("-ea", "-esa");
                /* Elassandra: -da after -ea — disable asserts in Cassandra packages after global -ea */
                test.jvmArgs("-da:org.apache.cassandra...");
            }"""
path.write_text(text.replace(needle, repl, 1), encoding="utf-8")
print("Patched OpenSearchTestBasePlugin (Cassandra -da after -ea) →", path)
PY
