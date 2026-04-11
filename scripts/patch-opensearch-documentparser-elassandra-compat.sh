#!/usr/bin/env bash
# OpenSearch 1.3: DocumentParser hides helpers Elassandra ElasticSecondaryIndex needs; add createCopyFields
# (value path) and expose nested* / dynamicOrDefault as public for org.elassandra.index.
#
# Usage: ./scripts/patch-opensearch-documentparser-elassandra-compat.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
DP="$DEST/server/src/main/java/org/opensearch/index/mapper/DocumentParser.java"
[[ -f "$DP" ]] || exit 0

python3 - "$DP" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
# Full apply = delegates patch (line 89 of opensearch-sidecar-prepare.sh) + visibility + at most one createCopyFields.
dup = "\n\n    /** Elassandra: createCopyFields — CQL secondary index copy_to path (fork parity). */"
anchor = "\n\n    // looks up a child mapper, but takes into account field names that expand to objects"
while (
    text.count("public static void createCopyFields(ParseContext context, List<String> copyToFields, Object value)") > 1
    and dup in text
):
    i = text.rfind(dup)
    j = text.find(anchor, i)
    if i == -1 or j == -1:
        break
    text = text[:i] + text[j:]
    print("DocumentParser: removed duplicate Elassandra createCopyFields block →", path)

_cf = text.count("public static void createCopyFields(ParseContext context, List<String> copyToFields, Object value)")
if (
    _cf == 1
    and "Elassandra: ES 6.8 static API for org.elassandra.index.ElasticSecondaryIndex" in text
    and "public static ParseContext nestedContext(ParseContext context, ObjectMapper mapper)" in text
    and "public static void nested(ParseContext context, ObjectMapper.Nested nested)" in text
    and "public static ObjectMapper.Dynamic dynamicOrDefault(ObjectMapper parentMapper, ParseContext context)" in text
):
    print("DocumentParser Elassandra compat already applied:", path)
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

# Fork / upstream may already ship public createCopyFields; do not insert a second method.
has_create = "public static void createCopyFields(ParseContext context, List<String> copyToFields, Object value)" in text
insert = ""
if not has_create:
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
if insert:
    text = text.replace(marker, insert + marker, 1)
else:
    print("DocumentParser: createCopyFields already present; skipping duplicate insert →", path)

if "import java.io.IOException;" not in text[:2000]:
    pass  # already have IOException via mapper imports
path.write_text(text, encoding="utf-8")
print("Patched", path)
PY
