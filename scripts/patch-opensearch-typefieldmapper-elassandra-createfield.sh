#!/usr/bin/env bash
# Restore Elassandra TypeFieldMapper#createField (fork parity).
set -euo pipefail

DEST="${1:?OpenSearch clone root}"
TF="$DEST/server/src/main/java/org/opensearch/index/mapper/TypeFieldMapper.java"
if [[ ! -f "$TF" ]]; then
  echo "Missing $TF" >&2
  exit 1
fi

python3 - "$TF" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

if "public void createField(ParseContext context, Object value, Optional<String> keyName)" in text:
    print(f"TypeFieldMapper already patched: {path}")
    sys.exit(0)

if "import java.util.Optional;\n" not in text:
    text = text.replace("import java.util.Objects;\n", "import java.util.Objects;\nimport java.util.Optional;\n", 1)

needle = """    @Override
    public void preParse(ParseContext context) {
        if (fieldType.indexOptions() == IndexOptions.NONE && !fieldType.stored()) {
            return;
        }
        context.doc().add(new Field(fieldType().name(), context.sourceToParse().type(), fieldType));
        if (fieldType().hasDocValues()) {
            context.doc().add(new SortedSetDocValuesField(fieldType().name(), new BytesRef(MapperService.SINGLE_MAPPING_NAME)));
        }
    }

    @Override
    protected String contentType() {
        return CONTENT_TYPE;
    }
"""

insert = """    @Override
    public void preParse(ParseContext context) {
        if (fieldType.indexOptions() == IndexOptions.NONE && !fieldType.stored()) {
            return;
        }
        context.doc().add(new Field(fieldType().name(), context.sourceToParse().type(), fieldType));
        if (fieldType().hasDocValues()) {
            context.doc().add(new SortedSetDocValuesField(fieldType().name(), new BytesRef(MapperService.SINGLE_MAPPING_NAME)));
        }
    }

    @Override
    public void createField(ParseContext context, Object value, Optional<String> keyName) {
        if (fieldType.indexOptions() == IndexOptions.NONE && !fieldType.stored()) {
            return;
        }
        context.doc().add(new Field(fieldType().name(), context.type(), fieldType));
        if (fieldType().hasDocValues()) {
            context.doc().add(new SortedSetDocValuesField(fieldType().name(), new BytesRef(context.type())));
        }
    }

    @Override
    protected String contentType() {
        return CONTENT_TYPE;
    }
"""

if needle not in text:
    print("TypeFieldMapper.java: anchor not found", file=sys.stderr)
    sys.exit(1)

path.write_text(text.replace(needle, insert, 1), encoding="utf-8")
print(f"Patched {path}")
PY
