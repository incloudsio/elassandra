#!/usr/bin/env bash
# OpenSearch 1.3: DocumentParser hides helpers Elassandra ElasticSecondaryIndex needs; add createCopyFields
# (value path) and expose nested* / dynamicOrDefault as public for org.elassandra.index.
#
# Usage: ./scripts/patch-opensearch-documentparser-elassandra-compat.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
DP="$DEST/server/src/main/java/org/opensearch/index/mapper/DocumentParser.java"
[[ -f "$DP" ]] || exit 0

if grep -q 'Elassandra: createCopyFields' "$DP"; then
  echo "DocumentParser Elassandra compat already applied: $DP"
  exit 0
fi

python3 - "$DP" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
if "Elassandra: createCopyFields" in text:
    print("DocumentParser compat already applied:", path)
    raise SystemExit(0)

text = text.replace(
    "    private static void nested(ParseContext context, ObjectMapper.Nested nested) {",
    "    public static void nested(ParseContext context, ObjectMapper.Nested nested) {",
    1,
)
text = text.replace(
    "    private static ParseContext nestedContext(ParseContext context, ObjectMapper mapper) {",
    "    public static ParseContext nestedContext(ParseContext context, ObjectMapper mapper) {",
    1,
)
text = text.replace(
    "    private static ObjectMapper.Dynamic dynamicOrDefault(ObjectMapper parentMapper, ParseContext context) {",
    "    public static ObjectMapper.Dynamic dynamicOrDefault(ObjectMapper parentMapper, ParseContext context) {",
    1,
)

insert = r'''
    /** Elassandra: createCopyFields — CQL secondary index copy_to path (fork parity). */
    public static void createCopyFields(ParseContext context, List<String> copyToFields, Object value) throws IOException {
        if (!context.isWithinCopyTo() && copyToFields.isEmpty() == false) {
            context = context.createCopyToContext();
            for (String field : copyToFields) {
                ParseContext.Document targetDoc = null;
                for (ParseContext.Document doc = context.doc(); doc != null; doc = doc.getParent()) {
                    if (field.startsWith(doc.getPrefix())) {
                        targetDoc = doc;
                        break;
                    }
                }
                assert targetDoc != null;
                final ParseContext copyToContext;
                if (targetDoc == context.doc()) {
                    copyToContext = context;
                } else {
                    copyToContext = context.switchDoc(targetDoc);
                }
                elassandraCreateCopy(field, copyToContext, value);
            }
        }
    }

    private static void elassandraCreateCopy(String field, ParseContext context, Object value) throws IOException {
        Mapper mapper = context.docMapper().mappers().getMapper(field);
        if (mapper != null && mapper instanceof FieldMapper) {
            ((FieldMapper) mapper).createField(context, value);
        } else {
            throw new IOException("CopyTo field " + field + " mapper not found");
        }
    }

'''

marker = "    // looks up a child mapper, but takes into account field names that expand to objects\n    private static Mapper getMapper("
if marker not in text:
    print("DocumentParser: getMapper anchor not found", file=sys.stderr)
    sys.exit(1)
text = text.replace(marker, insert + marker, 1)

if "import java.io.IOException;" not in text[:2000]:
    pass  # already have IOException via mapper imports
path.write_text(text, encoding="utf-8")
print("Patched", path)
PY
