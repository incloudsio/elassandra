#!/usr/bin/env bash
# ShardPath#resolveSnapshot (ES 6.8 fork) for ElasticSecondaryIndex.
#
# Usage: ./scripts/patch-opensearch-shard-path-resolve-snapshot.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
SP="$DEST/server/src/main/java/org/opensearch/index/shard/ShardPath.java"
[[ -f "$SP" ]] || exit 0

python3 - "$SP" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
if "resolveSnapshot()" in text:
    print("ShardPath.resolveSnapshot already present:", path)
    raise SystemExit(0)
if "public static final String TRANSLOG_FOLDER_NAME" not in text:
    print("unexpected ShardPath", file=sys.stderr)
    sys.exit(1)
text = text.replace(
    "    public static final String TRANSLOG_FOLDER_NAME = \"translog\";\n",
    "    public static final String TRANSLOG_FOLDER_NAME = \"translog\";\n"
    "    public static final String SNAPSHOT_FOLDER_NAME = \"snapshots\";\n",
    1,
)
needle = """    public Path resolveTranslog() {
        return path.resolve(TRANSLOG_FOLDER_NAME);
    }

    public Path resolveIndex() {"""
if needle not in text:
    print("patch: resolveTranslog anchor not found", file=sys.stderr)
    sys.exit(1)
repl = """    public Path resolveTranslog() {
        return path.resolve(TRANSLOG_FOLDER_NAME);
    }

    public Path resolveSnapshot() {
        return path.getParent().getParent().resolveSibling(SNAPSHOT_FOLDER_NAME);
    }

    public Path resolveIndex() {"""
path.write_text(text.replace(needle, repl, 1), encoding="utf-8")
print("Patched ShardPath.resolveSnapshot →", path)
PY
