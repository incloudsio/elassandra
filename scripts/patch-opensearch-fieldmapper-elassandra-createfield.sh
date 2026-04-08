#!/usr/bin/env bash
# Restore Elassandra secondary-index API: FieldMapper#createField and MultiFields#create (fork parity).
# Required by org.elassandra.index.ElasticSecondaryIndex and DocumentParser paths.
#
# Usage: ./scripts/patch-opensearch-fieldmapper-elassandra-createfield.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
FM="$DEST/server/src/main/java/org/opensearch/index/mapper/FieldMapper.java"
if [[ ! -f "$FM" ]]; then
  echo "Missing $FM" >&2
  exit 1
fi
if grep -q 'Elassandra: createField for secondary index' "$FM"; then
  echo "FieldMapper already patched: $FM"
  exit 0
fi

python3 - "$FM" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

if "import java.util.Optional;" not in text:
    text = text.replace("import java.util.Objects;\n", "import java.util.Objects;\nimport java.util.Optional;\n", 1)

needle = """    protected final void createFieldNamesField(ParseContext context) {
        assert fieldType().hasDocValues() == false : \"_field_names should only be used when doc_values are turned off\";
        FieldNamesFieldType fieldNamesFieldType = context.docMapper().metadataMapper(FieldNamesFieldMapper.class).fieldType();
        if (fieldNamesFieldType != null && fieldNamesFieldType.isEnabled()) {
            for (String fieldName : FieldNamesFieldMapper.extractFieldNames(fieldType().name())) {
                context.doc().add(new Field(FieldNamesFieldMapper.NAME, fieldName, FieldNamesFieldMapper.Defaults.FIELD_TYPE));
            }
        }
    }

    @Override
    public Iterator<Mapper> iterator() {"""

insert = """    protected final void createFieldNamesField(ParseContext context) {
        assert fieldType().hasDocValues() == false : \"_field_names should only be used when doc_values are turned off\";
        FieldNamesFieldType fieldNamesFieldType = context.docMapper().metadataMapper(FieldNamesFieldMapper.class).fieldType();
        if (fieldNamesFieldType != null && fieldNamesFieldType.isEnabled()) {
            for (String fieldName : FieldNamesFieldMapper.extractFieldNames(fieldType().name())) {
                context.doc().add(new Field(FieldNamesFieldMapper.NAME, fieldName, FieldNamesFieldMapper.Defaults.FIELD_TYPE));
            }
        }
    }

    /**
     * Elassandra: createField for secondary index / CQL document materialization (fork parity).
     */
    public final void createField(ParseContext context, Object value) throws IOException {
        createField(context, value, Optional.empty());
    }

    /**
     * Elassandra: createField for secondary index / CQL document materialization (fork parity).
     */
    public void createField(ParseContext context, Object value, Optional<String> keyName) throws IOException {
        multiFields.create(this, context, value);
    }

    @Override
    public Iterator<Mapper> iterator() {"""

if needle not in text:
    print("FieldMapper.java: anchor not found", file=sys.stderr)
    sys.exit(1)
text = text.replace(needle, insert, 1)

# MultiFields.parse block — append create() after parse()
needle2 = """        public void parse(FieldMapper mainField, ParseContext context) throws IOException {
            // TODO: multi fields are really just copy fields, we just need to expose \"sub fields\" or something that can be part
            // of the mappings
            if (mappers.isEmpty()) {
                return;
            }

            context = context.createMultiFieldContext();

            context.path().add(mainField.simpleName());
            for (ObjectCursor<FieldMapper> cursor : mappers.values()) {
                cursor.value.parse(context);
            }
            context.path().remove();
        }

        public MultiFields merge(MultiFields mergeWith) {"""

insert2 = """        public void parse(FieldMapper mainField, ParseContext context) throws IOException {
            // TODO: multi fields are really just copy fields, we just need to expose \"sub fields\" or something that can be part
            // of the mappings
            if (mappers.isEmpty()) {
                return;
            }

            context = context.createMultiFieldContext();

            context.path().add(mainField.simpleName());
            for (ObjectCursor<FieldMapper> cursor : mappers.values()) {
                cursor.value.parse(context);
            }
            context.path().remove();
        }

        /** Elassandra: propagate createField to multi-fields (fork parity). */
        public void create(FieldMapper mainField, ParseContext context, Object val) throws IOException {
            if (mappers.isEmpty()) {
                return;
            }
            context = context.createMultiFieldContext();
            context.path().add(mainField.simpleName());
            for (ObjectCursor<FieldMapper> cursor : mappers.values()) {
                cursor.value.createField(context, val, Optional.empty());
            }
            context.path().remove();
        }

        public MultiFields merge(MultiFields mergeWith) {"""

if needle2 not in text:
    print("FieldMapper.java: MultiFields anchor not found", file=sys.stderr)
    sys.exit(1)
text = text.replace(needle2, insert2, 1)

path.write_text(text, encoding="utf-8")
print("Patched", path)
PY
