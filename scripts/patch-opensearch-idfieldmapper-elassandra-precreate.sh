#!/usr/bin/env bash
# IdFieldMapper: restore Elassandra secondary-index _id materialization on OpenSearch 1.3.
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
F="$DEST/server/src/main/java/org/opensearch/index/mapper/IdFieldMapper.java"
[[ -f "$F" ]] || exit 0

python3 - "$F" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

if "public void createField(ParseContext context, Object value, Optional<String> keyName)" in text:
    print(f"IdFieldMapper Elassandra hooks already patched: {path}")
    sys.exit(0)

import_needle = "import java.util.List;\n"
import_replacement = "import java.util.List;\nimport java.util.Optional;\n"
if "import java.util.Optional;" not in text:
    if import_needle not in text:
        print(f"IdFieldMapper import anchor missing: {path}", file=sys.stderr)
        sys.exit(1)
    text = text.replace(import_needle, import_replacement, 1)

needle = """    @Override
    public void preParse(ParseContext context) {
        BytesRef id = Uid.encodeId(context.sourceToParse().id());
        context.doc().add(new Field(NAME, id, Defaults.FIELD_TYPE));
    }
"""

replacement = """    @Override
    public void preParse(ParseContext context) {
        BytesRef id = Uid.encodeId(context.sourceToParse().id());
        context.doc().add(new Field(NAME, id, Defaults.FIELD_TYPE));
    }

    @Override
    public void preCreate(Object indexingContext) {
        if (indexingContext instanceof ParseContext) {
            ParseContext context = (ParseContext) indexingContext;
            if (context.id() != null) {
                context.doc().add(new Field(NAME, Uid.encodeId(context.id()), Defaults.FIELD_TYPE));
            }
        }
    }

    @Override
    public void createField(ParseContext context, Object value, Optional<String> keyName) throws IOException {
        if (context.doc().getField(NAME) != null || value == null) {
            return;
        }
        final String id = value instanceof Uid ? ((Uid) value).id() : value.toString();
        context.doc().add(new Field(NAME, Uid.encodeId(id), Defaults.FIELD_TYPE));
    }
"""

if needle not in text:
    print(f"IdFieldMapper preParse anchor missing: {path}", file=sys.stderr)
    sys.exit(1)

text = text.replace(needle, replacement, 1)
path.write_text(text, encoding="utf-8")
print(f"Patched IdFieldMapper Elassandra hooks: {path}")
PY
