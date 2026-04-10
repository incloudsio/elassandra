#!/usr/bin/env bash
# Expose ES 6.8 DocumentParser static helpers used by ElasticSecondaryIndex (same package = access to private statics).
#
# Usage: ./scripts/patch-opensearch-document-parser-elassandra-delegates.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
DP="$DEST/server/src/main/java/org/opensearch/index/mapper/DocumentParser.java"
[[ -f "$DP" ]] || exit 0

# Wildcard imports in org.elassandra only pull public types; stock OS uses package-private DocumentParser.
perl -i -pe 's/^final class DocumentParser/public final class DocumentParser/' "$DP"

python3 - "$DP" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
# createCopyFields may exist from upstream or a partial run; still need Elassandra static wrappers.
if "elassandraNestedContext" in text:
    print("DocumentParser Elassandra delegates already present:", path)
    raise SystemExit(0)
if not text.rstrip().endswith("}"):
    print("unexpected DocumentParser end", file=sys.stderr)
    sys.exit(1)
insert = r'''
    // --- Elassandra: ES 6.8 static API for org.elassandra.index.ElasticSecondaryIndex ---
    public static ParseContext elassandraNestedContext(ParseContext context, ObjectMapper mapper) {
        return nestedContext(context, mapper);
    }

    public static ObjectMapper.Dynamic elassandraDynamicOrDefault(ObjectMapper parentMapper, ParseContext context) {
        return dynamicOrDefault(parentMapper, context);
    }

    public static void elassandraNested(ParseContext context, ObjectMapper.Nested nested) {
        nested(context, nested);
    }
'''
# Insert before final closing brace of file
idx = text.rfind("\n}")
if idx == -1:
    print("no closing brace", file=sys.stderr)
    sys.exit(1)
path.write_text(text[:idx] + insert + text[idx:], encoding="utf-8")
print("Patched DocumentParser Elassandra delegates →", path)
PY
