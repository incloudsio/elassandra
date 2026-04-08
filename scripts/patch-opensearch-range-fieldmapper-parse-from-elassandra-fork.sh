#!/usr/bin/env bash
# Insert RangeFieldMapper#parse(Object) from the Elassandra ES 6.8 fork, adapted for OpenSearch APIs.
#
# Usage: ./scripts/patch-opensearch-range-fieldmapper-parse-from-elassandra-fork.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${1:?OpenSearch clone root}"
SRC="$ROOT/server/src/main/java/org/elasticsearch/index/mapper/RangeFieldMapper.java"
RF="$DEST/server/src/main/java/org/opensearch/index/mapper/RangeFieldMapper.java"
[[ -f "$SRC" ]] && [[ -f "$RF" ]] || exit 0

python3 - "$SRC" "$RF" <<'PY'
from pathlib import Path
import sys
src_path, rf_path = Path(sys.argv[1]), Path(sys.argv[2])
text = src_path.read_text(encoding="utf-8")
start = text.find("    public Range parse(Object value)")
if start < 0:
    print("parse(Object) not found in fork", file=sys.stderr)
    sys.exit(1)
sub = text[start:]
end = sub.find("\n\n    @Override\n    protected void parseCreateField")
if end < 0:
    end = sub.find("\n    @Override\n    protected void parseCreateField")
if end < 0:
    print("end anchor not found after parse()", file=sys.stderr)
    sys.exit(1)
# Do not use strip(): it removes leading indent from the first line (public Range parse...).
block = sub[:end].rstrip() + "\n"

block = block.replace("org.elasticsearch", "org.opensearch")
block = block.replace("coerce.value()", "coerce()")
block = block.replace(
    "ElassandraDaemon.instance.node().getNamedXContentRegistry()",
    "org.opensearch.common.xcontent.NamedXContentRegistry.EMPTY",
)
block = block.replace(
    "JsonXContent.jsonXContent",
    "org.opensearch.common.xcontent.json.JsonXContent.jsonXContent",
)
block = block.replace("XContentFactory.", "org.opensearch.common.xcontent.XContentFactory.")
block = block.replace("XContentType.", "org.opensearch.common.xcontent.XContentType.")
block = block.replace("BytesReference.", "org.opensearch.common.bytes.BytesReference.")
block = block.replace("DeprecationHandler.", "org.opensearch.common.xcontent.DeprecationHandler.")
block = block.replace("XContentBuilder ", "org.opensearch.common.xcontent.XContentBuilder ")

old_ip = """        if (value instanceof String && fieldType().rangeType == RangeType.IP) {
            return parseIpRangeFromCidr((String) value);
        }"""
new_ip = (
    "        if (value instanceof String && fieldType().rangeType == RangeType.IP) {\n"
    "            org.opensearch.common.xcontent.XContentParser __p =\n"
    "                org.opensearch.common.xcontent.json.JsonXContent.jsonXContent.createParser(\n"
    "                    org.opensearch.common.xcontent.NamedXContentRegistry.EMPTY,\n"
    "                    org.opensearch.common.xcontent.DeprecationHandler.THROW_UNSUPPORTED_OPERATION,\n"
    "                    \"\\\"\" + (String) value + \"\\\"\");\n"
    "            __p.nextToken();\n"
    "            return parseIpRangeFromCidr(__p);\n"
    "        }"
)
if old_ip in block:
    block = block.replace(old_ip, new_ip, 1)

rf = rf_path.read_text(encoding="utf-8")
if "public Range parse(Object value)" in rf:
    print("parse(Object) already in OpenSearch RangeFieldMapper")
    raise SystemExit(0)
marker = "    private static Range parseIpRangeFromCidr"
if marker not in rf:
    print("marker not found in", rf_path, file=sys.stderr)
    sys.exit(1)
rf_path.write_text(rf.replace(marker, block + "\n    " + marker, 1), encoding="utf-8")
print("Inserted parse(Object) →", rf_path)
PY
