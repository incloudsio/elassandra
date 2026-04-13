#!/usr/bin/env bash
# ElasticQueryHandler: OpenSearch 1.3 side-car searches should not restrict by legacy mapping type.
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
F="$DEST/server/src/main/java/org/elassandra/index/ElasticQueryHandler.java"
[[ -f "$F" ]] || exit 0

python3 - "$F" <<'PY'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
if ".setTypes(" not in text:
    print(f"ElasticQueryHandler typeless search already patched: {path}")
    sys.exit(0)
pattern = re.compile(
    r"""(?P<prefix>\s*SearchRequestBuilder srb = client\.prepareSearch\(indices\)\n\s*\.setSource\(ssb\))\n\s*\.setTypes\([^\n]+\);"""
)
if not pattern.search(text):
    print(f"ElasticQueryHandler setTypes anchor missing: {path}", file=sys.stderr)
    sys.exit(1)
text = pattern.sub(r"\g<prefix>;", text, count=1)
path.write_text(text, encoding="utf-8")
print(f"Patched ElasticQueryHandler typeless search request: {path}")
PY
