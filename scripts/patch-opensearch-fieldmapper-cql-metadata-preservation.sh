#!/usr/bin/env bash
# Preserve Elassandra cql_* metadata for OpenSearch 1.3 leaf field mappers.
# This restores cql_collection / primary-key hints that ParametrizedFieldMapper
# currently drops, and teaches FieldMapper how to surface the preserved values
# back to SchemaManager / QueryManager.
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
python3 - "$DEST" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])


def write_if_changed(path: Path, new: str) -> None:
    old = path.read_text(encoding="utf-8") if path.exists() else None
    if old == new:
        print("unchanged", path)
        return
    path.write_text(new, encoding="utf-8")
    print("patched", path)


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        print(label, file=sys.stderr)
        sys.exit(1)
    return text.replace(old, new, 1)


fm = root / "server/src/main/java/org/opensearch/index/mapper/FieldMapper.java"
if fm.exists():
    text = fm.read_text(encoding="utf-8")
    text = text.replace("value == null || value.isBlank()", "value == null || value.trim().isEmpty()")
    if "Elassandra CQL builder metadata helpers" not in text:
        old = """        /** Set metadata on this field. */
        public T meta(Map<String, String> meta) {
            this.meta = meta;
            return (T) this;
        }
"""
        new = """        /** Set metadata on this field. */
        public T meta(Map<String, String> meta) {
            if (this.meta.isEmpty()) {
                this.meta = meta;
            } else {
                Map<String, String> merged = new HashMap<>(this.meta);
                merged.putAll(meta);
                this.meta = merged;
            }
            return (T) this;
        }

        /** Elassandra CQL builder metadata helpers. */
        private void putElassandraCqlMeta(String key, String value) {
            if (this.meta.isEmpty()) {
                this.meta = new HashMap<>();
            } else if ((this.meta instanceof HashMap) == false) {
                this.meta = new HashMap<>(this.meta);
            }
            this.meta.put(key, value);
        }

        public T cqlCollection(CqlMapper.CqlCollection cqlCollection) {
            putElassandraCqlMeta(TypeParsers.CQL_COLLECTION, cqlCollection.name().toLowerCase(java.util.Locale.ROOT));
            return builder;
        }

        public T cqlStruct(CqlMapper.CqlStruct cqlStruct) {
            putElassandraCqlMeta(TypeParsers.CQL_STRUCT, cqlStruct.name().toLowerCase(java.util.Locale.ROOT));
            return builder;
        }

        public T cqlType(String cqlType) {
            putElassandraCqlMeta(TypeParsers.CQL_TYPE, cqlType);
            return builder;
        }

        public T cqlPartialUpdate(boolean cqlPartialUpdate) {
            putElassandraCqlMeta(TypeParsers.CQL_MANDATORY, Boolean.toString(cqlPartialUpdate));
            return builder;
        }

        public T cqlPartitionKey(boolean cqlPartitionKey) {
            putElassandraCqlMeta(TypeParsers.CQL_PARTITION_KEY, Boolean.toString(cqlPartitionKey));
            return builder;
        }

        public T cqlStaticColumn(boolean cqlStaticColumn) {
            putElassandraCqlMeta(TypeParsers.CQL_STATIC_COLUMN, Boolean.toString(cqlStaticColumn));
            return builder;
        }

        public T cqlPrimaryKeyOrder(int cqlPrimaryKeyOrder) {
            putElassandraCqlMeta(TypeParsers.CQL_PRIMARY_KEY_ORDER, Integer.toString(cqlPrimaryKeyOrder));
            return builder;
        }

        public T cqlClusteringKeyDesc(boolean cqlClusteringKeyDesc) {
            putElassandraCqlMeta(TypeParsers.CQL_CLUSTERING_KEY_DESC, Boolean.toString(cqlClusteringKeyDesc));
            return builder;
        }

        public void cqlCheck() {
            if (Boolean.parseBoolean(this.meta.getOrDefault(TypeParsers.CQL_PARTITION_KEY, "false"))
                && Integer.parseInt(this.meta.getOrDefault(TypeParsers.CQL_PRIMARY_KEY_ORDER, "-1")) < 0) {
                throw new MapperParsingException(
                    "Partition key [" + name + "] has no primary key order, please set " + TypeParsers.CQL_PRIMARY_KEY_ORDER + "."
                );
            }
            if (Boolean.parseBoolean(this.meta.getOrDefault(TypeParsers.CQL_STATIC_COLUMN, "false"))
                && (Integer.parseInt(this.meta.getOrDefault(TypeParsers.CQL_PRIMARY_KEY_ORDER, "-1")) > 0
                    || Boolean.parseBoolean(this.meta.getOrDefault(TypeParsers.CQL_PARTITION_KEY, "false")))) {
                throw new MapperParsingException("Static column [" + name + "] cannot be part of the primary key.");
            }
            if (Boolean.parseBoolean(this.meta.getOrDefault(TypeParsers.CQL_CLUSTERING_KEY_DESC, "false"))
                && (Boolean.parseBoolean(this.meta.getOrDefault(TypeParsers.CQL_PARTITION_KEY, "false"))
                    || Integer.parseInt(this.meta.getOrDefault(TypeParsers.CQL_PRIMARY_KEY_ORDER, "-1")) < 0)) {
                throw new MapperParsingException(
                    "Clustering column [" + name + "] cannot be part of the partition key and should have a primary key order."
                );
            }
        }
"""
        text = replace_once(text, old, new, "FieldMapper.java: meta anchor not found")
    if "Elassandra CQL metadata helpers." not in text:
        old = """    /** Elassandra CQL column type for leaf fields (fork parity; side-car stub). */
    public org.apache.cassandra.cql3.CQL3Type.Raw rawType() {
        return org.apache.cassandra.cql3.CQL3Type.Raw.from(org.apache.cassandra.cql3.CQL3Type.Native.TEXT);
    }

}
"""
        new = """    /** Elassandra CQL metadata helpers. */
    private String elassandraCqlMeta(String key) {
        java.util.Map<String, String> meta = fieldType().meta();
        return meta == null ? null : meta.get(key);
    }

    private boolean elassandraCqlBoolean(String key, boolean defaultValue) {
        String value = elassandraCqlMeta(key);
        return value == null ? defaultValue : Boolean.parseBoolean(value);
    }

    private int elassandraCqlInt(String key, int defaultValue) {
        String value = elassandraCqlMeta(key);
        if (value == null) {
            return defaultValue;
        }
        try {
            return Integer.parseInt(value);
        } catch (NumberFormatException e) {
            return defaultValue;
        }
    }

    private static org.apache.cassandra.cql3.CQL3Type.Raw defaultRawType(String typeName) {
        switch (typeName) {
            case "keyword":
            case "text":
            case "completion":
                return org.apache.cassandra.cql3.CQL3Type.Raw.from(org.apache.cassandra.cql3.CQL3Type.Native.TEXT);
            case "integer":
            case "token_count":
                return org.apache.cassandra.cql3.CQL3Type.Raw.from(org.apache.cassandra.cql3.CQL3Type.Native.INT);
            case "long":
            case "unsigned_long":
                return org.apache.cassandra.cql3.CQL3Type.Raw.from(org.apache.cassandra.cql3.CQL3Type.Native.BIGINT);
            case "short":
                return org.apache.cassandra.cql3.CQL3Type.Raw.from(org.apache.cassandra.cql3.CQL3Type.Native.SMALLINT);
            case "byte":
                return org.apache.cassandra.cql3.CQL3Type.Raw.from(org.apache.cassandra.cql3.CQL3Type.Native.TINYINT);
            case "double":
            case "scaled_float":
                return org.apache.cassandra.cql3.CQL3Type.Raw.from(org.apache.cassandra.cql3.CQL3Type.Native.DOUBLE);
            case "float":
            case "half_float":
                return org.apache.cassandra.cql3.CQL3Type.Raw.from(org.apache.cassandra.cql3.CQL3Type.Native.FLOAT);
            case "boolean":
                return org.apache.cassandra.cql3.CQL3Type.Raw.from(org.apache.cassandra.cql3.CQL3Type.Native.BOOLEAN);
            case "date":
                return org.apache.cassandra.cql3.CQL3Type.Raw.from(org.apache.cassandra.cql3.CQL3Type.Native.TIMESTAMP);
            case "binary":
                return org.apache.cassandra.cql3.CQL3Type.Raw.from(org.apache.cassandra.cql3.CQL3Type.Native.BLOB);
            case "ip":
                return org.apache.cassandra.cql3.CQL3Type.Raw.from(org.apache.cassandra.cql3.CQL3Type.Native.INET);
            default:
                return org.apache.cassandra.cql3.CQL3Type.Raw.from(org.apache.cassandra.cql3.CQL3Type.Native.TEXT);
        }
    }

    private org.apache.cassandra.cql3.CQL3Type.Raw configuredRawType() {
        String value = elassandraCqlMeta(TypeParsers.CQL_TYPE);
        if (value == null || value.trim().isEmpty()) {
            return null;
        }
        try {
            return org.apache.cassandra.cql3.CQLFragmentParser.parseAny(
                org.apache.cassandra.cql3.CqlParser::comparatorType,
                value,
                "CQL type"
            );
        } catch (RuntimeException e) {
            return null;
        }
    }

    @Override
    public CqlMapper.CqlCollection cqlCollection() {
        String value = elassandraCqlMeta(TypeParsers.CQL_COLLECTION);
        if (value == null) {
            return name().startsWith("_") ? CqlMapper.CqlCollection.NONE : CqlMapper.CqlCollection.LIST;
        }
        switch (value.toLowerCase(java.util.Locale.ROOT)) {
            case "list":
                return CqlMapper.CqlCollection.LIST;
            case "set":
                return CqlMapper.CqlCollection.SET;
            case "singleton":
                return CqlMapper.CqlCollection.SINGLETON;
            default:
                return CqlMapper.CqlCollection.NONE;
        }
    }

    @Override
    public String cqlCollectionTag() {
        switch (cqlCollection()) {
            case LIST:
                return "list";
            case SET:
                return "set";
            default:
                return "";
        }
    }

    @Override
    public CqlMapper.CqlStruct cqlStruct() {
        String value = elassandraCqlMeta(TypeParsers.CQL_STRUCT);
        if (value == null) {
            return CqlMapper.CqlStruct.UDT;
        }
        switch (value.toLowerCase(java.util.Locale.ROOT)) {
            case "map":
                return CqlMapper.CqlStruct.MAP;
            case "opaque_map":
                return CqlMapper.CqlStruct.OPAQUE_MAP;
            case "tuple":
                return CqlMapper.CqlStruct.TUPLE;
            default:
                return CqlMapper.CqlStruct.UDT;
        }
    }

    @Override
    public boolean cqlPartialUpdate() {
        return elassandraCqlBoolean(TypeParsers.CQL_MANDATORY, false);
    }

    @Override
    public boolean cqlPartitionKey() {
        return elassandraCqlBoolean(TypeParsers.CQL_PARTITION_KEY, false);
    }

    @Override
    public boolean cqlStaticColumn() {
        return elassandraCqlBoolean(TypeParsers.CQL_STATIC_COLUMN, false);
    }

    @Override
    public int cqlPrimaryKeyOrder() {
        return elassandraCqlInt(TypeParsers.CQL_PRIMARY_KEY_ORDER, -1);
    }

    @Override
    public boolean cqlClusteringKeyDesc() {
        return elassandraCqlBoolean(TypeParsers.CQL_CLUSTERING_KEY_DESC, false);
    }

    public org.apache.cassandra.cql3.CQL3Type.Raw rawType() {
        org.apache.cassandra.cql3.CQL3Type.Raw configured = configuredRawType();
        return configured != null ? configured : defaultRawType(typeName());
    }

}
"""
        text = replace_once(text, old, new, "FieldMapper.java: rawType anchor not found")
    text = text.replace(
        """    @Override
    public CqlMapper.CqlCollection cqlCollection() {
        String value = elassandraCqlMeta(TypeParsers.CQL_COLLECTION);
        if (value == null) {
            return CqlMapper.CqlCollection.NONE;
        }
""",
        """    @Override
    public CqlMapper.CqlCollection cqlCollection() {
        String value = elassandraCqlMeta(TypeParsers.CQL_COLLECTION);
        if (value == null) {
            return name().startsWith("_") ? CqlMapper.CqlCollection.NONE : CqlMapper.CqlCollection.LIST;
        }
""",
    )
    text = text.replace(
        """    @Override
    public CqlMapper.CqlCollection cqlCollection() {
        String value = elassandraCqlMeta(TypeParsers.CQL_COLLECTION);
        if (value == null) {
            return CqlMapper.CqlCollection.LIST;
        }
""",
        """    @Override
    public CqlMapper.CqlCollection cqlCollection() {
        String value = elassandraCqlMeta(TypeParsers.CQL_COLLECTION);
        if (value == null) {
            return name().startsWith("_") ? CqlMapper.CqlCollection.NONE : CqlMapper.CqlCollection.LIST;
        }
""",
    )
    text = text.replace(
        """    @Override
    public CqlMapper.CqlCollection cqlCollection() {
        String value = elassandraCqlMeta(TypeParsers.CQL_COLLECTION);
        if (value == null) {
            return name().startsWith("_") ? CqlMapper.CqlCollection.SINGLETON : CqlMapper.CqlCollection.LIST;
        }
""",
        """    @Override
    public CqlMapper.CqlCollection cqlCollection() {
        String value = elassandraCqlMeta(TypeParsers.CQL_COLLECTION);
        if (value == null) {
            return name().startsWith("_") ? CqlMapper.CqlCollection.NONE : CqlMapper.CqlCollection.LIST;
        }
""",
    )
    write_if_changed(fm, text)


pfm = root / "server/src/main/java/org/opensearch/index/mapper/ParametrizedFieldMapper.java"
if pfm.exists():
    text = pfm.read_text(encoding="utf-8")
    if 'protected final Map<String, String> elassandraCqlMetadata = new HashMap<>();' not in text:
        old = """        protected final MultiFields.Builder multiFieldsBuilder = new MultiFields.Builder();
        protected final CopyTo.Builder copyTo = new CopyTo.Builder();
"""
        new = """        protected final MultiFields.Builder multiFieldsBuilder = new MultiFields.Builder();
        protected final CopyTo.Builder copyTo = new CopyTo.Builder();
        protected final Map<String, String> elassandraCqlMetadata = new HashMap<>();
"""
        text = replace_once(text, old, new, "ParametrizedFieldMapper.java: builder fields anchor not found")
        text = text.replace(
            '                if (parameter == null && propName.startsWith("cql_")) {\n'
            '                    iterator.remove();\n'
            '                    continue;\n'
            '                }\n',
            '                if (parameter == null && propName.startsWith("cql_")) {\n'
            '                    elassandraCqlMetadata.put(propName, String.valueOf(propNode));\n'
            '                    iterator.remove();\n'
            '                    continue;\n'
            '                }\n',
            1,
        )
        old = """                parameter.parse(name, parserContext, propNode);
                iterator.remove();
            }
            validate();
        }
"""
        new = """                parameter.parse(name, parserContext, propNode);
                iterator.remove();
            }
            if (elassandraCqlMetadata.isEmpty() == false) {
                Parameter<?> metaParameter = paramsMap.get("meta");
                if (metaParameter instanceof Parameter<?>) {
                    @SuppressWarnings("unchecked")
                    Parameter<Map<String, String>> typedMeta = (Parameter<Map<String, String>>) metaParameter;
                    Map<String, String> mergedMeta = new HashMap<>(typedMeta.getValue());
                    mergedMeta.putAll(elassandraCqlMetadata);
                    typedMeta.setValue(mergedMeta);
                }
            }
            validate();
        }
"""
        text = replace_once(text, old, new, "ParametrizedFieldMapper.java: parse tail anchor not found")
    write_if_changed(pfm, text)


tp = root / "server/src/main/java/org/opensearch/index/mapper/TypeParsers.java"
if tp.exists():
    text = tp.read_text(encoding="utf-8")
    if "private static boolean parseElassandraCqlField(\n        FieldMapper.Builder<?> builder," not in text:
        old = """    private static boolean parseElassandraCqlField(Iterator<Map.Entry<String, Object>> iterator, String propName) {
        if (isElassandraCqlField(propName)) {
            iterator.remove();
            return true;
        }
        return false;
    }

    /**
     * Parse the {@code meta} key of the mapping.
     */
"""
        new = """    private static boolean parseElassandraCqlField(
        FieldMapper.Builder<?> builder,
        Iterator<Map.Entry<String, Object>> iterator,
        String propName,
        Object propNode
    ) {
        if (isElassandraCqlField(propName) == false) {
            return false;
        }
        if (CQL_MANDATORY.equals(propName)) {
            builder.cqlPartialUpdate(XContentMapValues.nodeBooleanValue(propNode, propName));
        } else if (CQL_COLLECTION.equals(propName)) {
            String value = propNode.toString().toLowerCase(java.util.Locale.ROOT);
            switch (value) {
                case "list":
                    builder.cqlCollection(CqlMapper.CqlCollection.LIST);
                    break;
                case "set":
                    builder.cqlCollection(CqlMapper.CqlCollection.SET);
                    break;
                case "singleton":
                    builder.cqlCollection(CqlMapper.CqlCollection.SINGLETON);
                    break;
                default:
                    builder.cqlCollection(CqlMapper.CqlCollection.NONE);
                    break;
            }
        } else if (CQL_STRUCT.equals(propName)) {
            String value = propNode.toString().toLowerCase(java.util.Locale.ROOT);
            switch (value) {
                case "map":
                    builder.cqlStruct(CqlMapper.CqlStruct.MAP);
                    break;
                case "opaque_map":
                    builder.cqlStruct(CqlMapper.CqlStruct.OPAQUE_MAP);
                    break;
                case "tuple":
                    builder.cqlStruct(CqlMapper.CqlStruct.TUPLE);
                    break;
                default:
                    builder.cqlStruct(CqlMapper.CqlStruct.UDT);
                    break;
            }
        } else if (CQL_TYPE.equals(propName)) {
            builder.cqlType(propNode.toString());
        } else if (CQL_PARTITION_KEY.equals(propName)) {
            builder.cqlPartitionKey(XContentMapValues.nodeBooleanValue(propNode, propName));
        } else if (CQL_STATIC_COLUMN.equals(propName)) {
            builder.cqlStaticColumn(XContentMapValues.nodeBooleanValue(propNode, propName));
        } else if (CQL_CLUSTERING_KEY_DESC.equals(propName)) {
            builder.cqlClusteringKeyDesc(XContentMapValues.nodeBooleanValue(propNode, propName));
        } else if (CQL_PRIMARY_KEY_ORDER.equals(propName)) {
            builder.cqlPrimaryKeyOrder(XContentMapValues.nodeIntegerValue(propNode));
        }
        iterator.remove();
        return true;
    }

    /**
     * Parse the {@code meta} key of the mapping.
     */
"""
        text = replace_once(text, old, new, "TypeParsers.java: parseElassandraCqlField anchor not found")
        old = """        @SuppressWarnings("unchecked")
        Map<String, ?> meta = (Map<String, ?>) metaObject;
        if (meta.size() > 5) {
            throw new MapperParsingException("[meta] can't have more than 5 entries, but got " + meta.size() + " on field [" + name + "]");
        }
        for (String key : meta.keySet()) {
            if (key.codePointCount(0, key.length()) > 20) {
                throw new MapperParsingException(
                    "[meta] keys can't be longer than 20 chars, but got [" + key + "] for field [" + name + "]"
                );
            }
        }
        for (Object value : meta.values()) {
"""
        new = """        @SuppressWarnings("unchecked")
        Map<String, ?> meta = (Map<String, ?>) metaObject;
        int userMetaEntries = 0;
        for (String key : meta.keySet()) {
            if (isElassandraCqlField(key)) {
                continue;
            }
            userMetaEntries++;
            if (key.codePointCount(0, key.length()) > 20) {
                throw new MapperParsingException(
                    "[meta] keys can't be longer than 20 chars, but got [" + key + "] for field [" + name + "]"
                );
            }
        }
        if (userMetaEntries > 5) {
            throw new MapperParsingException("[meta] can't have more than 5 entries, but got " + userMetaEntries + " on field [" + name + "]");
        }
        for (Object value : meta.values()) {
"""
        text = replace_once(text, old, new, "TypeParsers.java: parseMeta anchor not found")
        text = text.replace(
            '            } else if (parseElassandraCqlField(iterator, propName)) {\n'
            '                // Elassandra-specific mapping metadata is consumed by forked schema logic, not stock OpenSearch builders.\n'
            '            }\n',
            '            } else if (parseElassandraCqlField(builder, iterator, propName, propNode)) {\n'
            '                // Elassandra-specific mapping metadata is preserved on FieldMapper for SchemaManager / QueryManager.\n'
            '            }\n',
            1,
        )
    write_if_changed(tp, text)


ms = root / "server/src/main/java/org/opensearch/index/mapper/MapperService.java"
if ms.exists():
    text = ms.read_text(encoding="utf-8")
    if "private boolean mappingSourcesEqual(CompressedXContent left, CompressedXContent right) throws IOException" not in text:
        old = """    private void assertMappingVersion(
"""
        new = """    private boolean mappingSourcesEqual(CompressedXContent left, CompressedXContent right) throws IOException {
        if (left.equals(right)) {
            return true;
        }
        Map<String, Object> leftMap = XContentHelper.convertToMap(left.compressedReference(), true, XContentType.JSON).v2();
        Map<String, Object> rightMap = XContentHelper.convertToMap(right.compressedReference(), true, XContentType.JSON).v2();
        return leftMap.equals(rightMap);
    }

    private void assertMappingVersion(
"""
        text = replace_once(text, old, new, "MapperService.java: assertMappingVersion insertion anchor not found")
    text = text.replace("assert currentSource.equals(newSource) : ", "assert mappingSourcesEqual(currentSource, newSource) : ")
    text = text.replace("assert currentSource.equals(mapperSource) : ", "assert mappingSourcesEqual(currentSource, mapperSource) : ")
    text = text.replace("assert currentSource.equals(newSource) == false : ", "assert mappingSourcesEqual(currentSource, newSource) == false : ")
    if "Elassandra: tolerate semantically-equal mapping serialization" not in text:
        old = """        if (newMapper.mappingSource().equals(mappingSource) == false) {
            throw new IllegalStateException(
                "DocumentMapper serialization result is different from source. \\n--> Source ["
                    + mappingSource
                    + "]\\n--> Result ["
                    + newMapper.mappingSource()
                    + "]"
            );
        }
"""
        new = """        if (newMapper.mappingSource().equals(mappingSource) == false) {
            // Elassandra: tolerate semantically-equal mapping serialization when cql_* metadata is
            // preserved through a different but equivalent map ordering.
            Map<String, Object> sourceMap = XContentHelper.convertToMap(mappingSource.compressedReference(), true, XContentType.JSON).v2();
            Map<String, Object> resultMap = XContentHelper.convertToMap(newMapper.mappingSource().compressedReference(), true, XContentType.JSON).v2();
            if (sourceMap.equals(resultMap) == false) {
                throw new IllegalStateException(
                    "DocumentMapper serialization result is different from source. \\n--> Source ["
                        + mappingSource
                        + "]\\n--> Result ["
                        + newMapper.mappingSource()
                        + "]"
                );
            }
        }
"""
        text = replace_once(text, old, new, "MapperService.java: assertSerialization anchor not found")
    write_if_changed(ms, text)
PY
