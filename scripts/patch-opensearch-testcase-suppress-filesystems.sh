#!/usr/bin/env bash
# Lucene mock FS layers + java.io.tmpdir / embedded Cassandra: add @LuceneTestCase.SuppressFileSystems("*") on OpenSearchTestCase.
# Pair with gradle/opensearch-sidecar-elassandra.init.gradle (tmpdir + elassandra.disable.lucene.mock.filesystem).
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
F="$DEST/test/framework/src/main/java/org/opensearch/test/OpenSearchTestCase.java"
[[ -f "$F" ]] || exit 0

if grep -q 'SuppressFileSystems' "$F" 2>/dev/null; then
  echo "OpenSearchTestCase SuppressFileSystems already present → $F"
  exit 0
fi

python3 - "$F" <<'PY'
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
needle = "@LuceneTestCase.SuppressSysoutChecks(bugUrl = \"we log a lot on purpose\")"
if needle not in text:
    print("OpenSearchTestCase: expected @SuppressSysoutChecks line not found; skip →", path, file=sys.stderr)
    sys.exit(0)
insert = needle + "\n@LuceneTestCase.SuppressFileSystems(\"*\")"
path.write_text(text.replace(needle, insert, 1), encoding="utf-8")
print("Patched OpenSearchTestCase (@SuppressFileSystems) →", path)
PY
