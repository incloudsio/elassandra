#!/usr/bin/env bash
# Embedded single-node tests use path.data under Lucene mock FS; APFS often reports low % free on the
# host volume while absolute free space is ample — DiskThresholdMonitor then blocks allocation/recovery.
# Idempotent: inserts the setting if missing (sync from ESSingleNodeTestCase usually already includes it).
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
F="$DEST/test/framework/src/main/java/org/opensearch/test/OpenSearchSingleNodeTestCase.java"
[[ -f "$F" ]] || exit 0

if grep -q 'cluster.routing.allocation.disk.threshold_enabled' "$F" 2>/dev/null; then
  echo "OpenSearchSingleNodeTestCase: disk watermark patch already present → $F"
  exit 0
fi

python3 - "$F" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
needle = '                        .put("client.type", "node")\n'
insert = (
    needle
    + '                        .put("cluster.routing.allocation.disk.threshold_enabled", false)\n'
)
if needle not in text:
    print("OpenSearchSingleNodeTestCase: client.type anchor missing; skip disk watermark →", path, file=sys.stderr)
    sys.exit(1)
text = text.replace(needle, insert, 1)
path.write_text(text, encoding="utf-8")
print("Patched OpenSearchSingleNodeTestCase (disable disk watermarks) →", path)
PY
