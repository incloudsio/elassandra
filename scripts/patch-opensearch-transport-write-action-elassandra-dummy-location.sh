#!/usr/bin/env bash
# Restore Elassandra's dummy translog sync location for Cassandra-backed writes.
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
FILE="$DEST/server/src/main/java/org/opensearch/action/support/replication/TransportWriteAction.java"
[[ -f "$FILE" ]] || exit 0

python3 - "$FILE" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

if "return new Translog.Location(0, 0, 0);" in text:
    print(f"TransportWriteAction dummy location already patched: {path}")
    raise SystemExit(0)

needle = """    public static Location locationToSync(Location current, Location next) {
        /* here we are moving forward in the translog with each operation. Under the hood this might
         * cross translog files which is ok since from the user perspective the translog is like a
         * tape where only the highest location needs to be fsynced in order to sync all previous
         * locations even though they are not in the same file. When the translog rolls over files
         * the previous file is fsynced on after closing if needed.*/
        assert next != null : "next operation can't be null";
        assert current == null || current.compareTo(next) < 0 : "translog locations are not increasing";
        return next;
    }"""
replacement = """    public static Location locationToSync(Location current, Location next) {
        /* here we are moving forward in the translog with each operation. Under the hood this might
         * cross translog files which is ok since from the user perspective the translog is like a
         * tape where only the highest location needs to be fsynced in order to sync all previous
         * locations even though they are not in the same file. When the translog rolls over files
         * the previous file is fsynced on after closing if needed.*/
        return new Translog.Location(0, 0, 0);
    }"""
if needle not in text:
    print(f"TransportWriteAction locationToSync anchor missing: {path}", file=sys.stderr)
    sys.exit(1)

path.write_text(text.replace(needle, replacement, 1), encoding="utf-8")
print(f"Patched TransportWriteAction dummy location: {path}")
PY
