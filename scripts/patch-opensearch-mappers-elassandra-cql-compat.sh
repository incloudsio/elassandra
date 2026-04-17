#!/usr/bin/env bash
# Make stock OpenSearch 1.3 mappers satisfy Elassandra SchemaManager compile expectations.
#
# Usage: ./scripts/patch-opensearch-mappers-elassandra-cql-compat.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
python3 - "$DEST" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])

def write_if_changed(path: Path, new: str) -> None:
    old = path.read_text(encoding="utf-8") if path.exists() else None
    if old == new:
        print("unchanged", path)
        return
    path.write_text(new, encoding="utf-8")
    print("patched", path)

M = root / "server/src/main/java/org/opensearch/index/mapper/Mapper.java"
if M.exists():
    t = M.read_text(encoding="utf-8")
    if "Elassandra: whether this mapper" not in t:
        needle = """    protected static boolean hasIndexCreated(Settings settings) {
        return settings.hasValue(IndexMetadata.SETTING_INDEX_VERSION_CREATED.getKey());
    }
}
"""
        repl = """    protected static boolean hasIndexCreated(Settings settings) {
        return settings.hasValue(IndexMetadata.SETTING_INDEX_VERSION_CREATED.getKey());
    }

    /**
     * Elassandra: whether this mapper contributes a mapped field (fork parity).
     */
    public boolean hasField() {
        return true;
    }
}
"""
        if needle not in t:
            print("Mapper.java: anchor not found", file=sys.stderr)
            sys.exit(1)
        t = t.replace(needle, repl, 1)
    # ParametrizedFieldMapper extends Mapper (not FieldMapper): Mapper must implement CqlMapper + cqlName().
    if "implements CqlMapper" not in t.split("{", 1)[0]:
        t = t.replace(
            "public abstract class Mapper implements ToXContentFragment, Iterable<Mapper> {",
            "public abstract class Mapper implements ToXContentFragment, Iterable<Mapper>, CqlMapper {",
            1,
        )
    if "ByteBuffer cqlName()" not in t:
        needle2 = """    public boolean hasField() {
        return true;
    }
}"""
        repl2 = """    public boolean hasField() {
        return true;
    }

    /** Elassandra: Cassandra column name bytes (fork parity). */
    @Override
    public java.nio.ByteBuffer cqlName() {
        return org.apache.cassandra.utils.ByteBufferUtil.bytes(simpleName());
    }
}"""
        if needle2 not in t:
            print("Mapper.java: hasField tail anchor not found (for cqlName)", file=sys.stderr)
            sys.exit(1)
        t = t.replace(needle2, repl2, 1)
    write_if_changed(M, t)

TP = root / "server/src/main/java/org/opensearch/index/mapper/TypeParsers.java"
if TP.exists():
    t = TP.read_text(encoding="utf-8")
    canonical_cql_constants = """    /** Elassandra mapping extension. */
    public static final String CQL_MANDATORY = "cql_mandatory";
    public static final String CQL_COLLECTION = "cql_collection";
    public static final String CQL_STRUCT = "cql_struct";
    public static final String CQL_TYPE = "cql_type";
    public static final String CQL_UDT_NAME = "cql_udt_name";
    public static final String CQL_PARTITION_KEY = "cql_partition_key";
    public static final String CQL_STATIC_COLUMN = "cql_static_column";
    public static final String CQL_CLUSTERING_KEY_DESC = "cql_clustering_key_desc";
    public static final String CQL_PRIMARY_KEY_ORDER = "cql_primary_key_order";
"""
    t = re.sub(
        r'    /\*\* Elassandra mapping extension\. \*/\n(?:    public static final String CQL_[A-Z_]+ = "cql_[a-z_]+";\n)+',
        canonical_cql_constants,
        t,
        count=1,
    )
    if "CQL_MANDATORY" not in t:
        needle = '    public static final String INDEX_OPTIONS_OFFSETS = "offsets";\n'
        repl = needle + "\n    /** Elassandra mapping extension. */\n    public static final String CQL_MANDATORY = \"cql_mandatory\";\n"
        if needle not in t:
            print("TypeParsers.java: OFFSETS anchor not found", file=sys.stderr)
            sys.exit(1)
        t = t.replace(needle, repl, 1)
    if "CQL_COLLECTION" not in t:
        needle = '    public static final String CQL_MANDATORY = "cql_mandatory";\n'
        repl = (
            needle
            + "    public static final String CQL_COLLECTION = \"cql_collection\";\n"
            + "    public static final String CQL_STRUCT = \"cql_struct\";\n"
            + "    public static final String CQL_UDT_NAME = \"cql_udt_name\";\n"
            + "    public static final String CQL_PARTITION_KEY = \"cql_partition_key\";\n"
            + "    public static final String CQL_STATIC_COLUMN = \"cql_static_column\";\n"
            + "    public static final String CQL_CLUSTERING_KEY_DESC = \"cql_clustering_key_desc\";\n"
            + "    public static final String CQL_PRIMARY_KEY_ORDER = \"cql_primary_key_order\";\n"
        )
        if needle not in t:
            print("TypeParsers.java: CQL_MANDATORY anchor not found (for extended CQL keys)", file=sys.stderr)
            sys.exit(1)
        t = t.replace(needle, repl, 1)
    if "CQL_TYPE" not in t:
        needle = '    public static final String CQL_STRUCT = "cql_struct";\n'
        repl = needle + '    public static final String CQL_TYPE = "cql_type";\n'
        if needle not in t:
            print("TypeParsers.java: CQL_STRUCT anchor not found (for CQL_TYPE)", file=sys.stderr)
            sys.exit(1)
        t = t.replace(needle, repl, 1)
    if "private static boolean isElassandraCqlField" not in t:
        needle = """    public static void checkNull(String propName, Object propNode) {
        if (false == propName.equals("null_value") && propNode == null) {
            /*
             * No properties *except* null_value are allowed to have null. So we catch it here and tell the user something useful rather
             * than send them a null pointer exception later.
             */
            throw new MapperParsingException("[" + propName + "] must not have a [null] value");
        }
    }

"""
        repl = """    public static void checkNull(String propName, Object propNode) {
        if (false == propName.equals("null_value") && propNode == null) {
            /*
             * No properties *except* null_value are allowed to have null. So we catch it here and tell the user something useful rather
             * than send them a null pointer exception later.
             */
            throw new MapperParsingException("[" + propName + "] must not have a [null] value");
        }
    }

    private static boolean isElassandraCqlField(String propName) {
        return CQL_MANDATORY.equals(propName)
            || CQL_COLLECTION.equals(propName)
            || CQL_STRUCT.equals(propName)
            || CQL_TYPE.equals(propName)
            || CQL_UDT_NAME.equals(propName)
            || CQL_PARTITION_KEY.equals(propName)
            || CQL_STATIC_COLUMN.equals(propName)
            || CQL_CLUSTERING_KEY_DESC.equals(propName)
            || CQL_PRIMARY_KEY_ORDER.equals(propName);
    }

    private static boolean parseElassandraCqlField(Iterator<Map.Entry<String, Object>> iterator, String propName) {
        if (isElassandraCqlField(propName)) {
            iterator.remove();
            return true;
        }
        return false;
    }

"""
        if needle not in t:
            print("TypeParsers.java: checkNull anchor not found (for Elassandra CQL compatibility)", file=sys.stderr)
            sys.exit(1)
        t = t.replace(needle, repl, 1)
    if (
        "parseElassandraCqlField(iterator, propName)" not in t
        and "parseElassandraCqlField(builder, iterator, propName, propNode)" not in t
    ):
        needle = """            } else if (propName.equals("copy_to")) {
                if (parserContext.isWithinMultiField()) {
                    throw new MapperParsingException(
                        "copy_to in multi fields is not allowed. Found the copy_to in field ["
                            + name
                            + "] "
                            + "which is within a multi field."
                    );
                } else {
                    List<String> copyFields = parseCopyFields(propNode);
                    FieldMapper.CopyTo.Builder cpBuilder = new FieldMapper.CopyTo.Builder();
                    copyFields.forEach(cpBuilder::add);
                    builder.copyTo(cpBuilder.build());
                }
                iterator.remove();
            }
"""
        repl = """            } else if (propName.equals("copy_to")) {
                if (parserContext.isWithinMultiField()) {
                    throw new MapperParsingException(
                        "copy_to in multi fields is not allowed. Found the copy_to in field ["
                            + name
                            + "] "
                            + "which is within a multi field."
                    );
                } else {
                    List<String> copyFields = parseCopyFields(propNode);
                    FieldMapper.CopyTo.Builder cpBuilder = new FieldMapper.CopyTo.Builder();
                    copyFields.forEach(cpBuilder::add);
                    builder.copyTo(cpBuilder.build());
                }
                iterator.remove();
            } else if (parseElassandraCqlField(iterator, propName)) {
                // Elassandra-specific mapping metadata is consumed by forked schema logic, not stock OpenSearch builders.
            }
"""
        if needle not in t:
            print("TypeParsers.java: parseField anchor not found (for Elassandra CQL compatibility)", file=sys.stderr)
            sys.exit(1)
        t = t.replace(needle, repl, 1)
    write_if_changed(TP, t)

DMP = root / "server/src/main/java/org/opensearch/index/mapper/DocumentMapperParser.java"
if DMP.exists():
    t = DMP.read_text(encoding="utf-8")
    if "private static boolean isElassandraCqlField(Object key)" not in t:
        needle = """    public static void checkNoRemainingFields(Map<?, ?> fieldNodeMap, Version indexVersionCreated, String message) {
        if (!fieldNodeMap.isEmpty()) {
            throw new MapperParsingException(message + getRemainingFields(fieldNodeMap));
        }
    }

"""
        repl = """    public static void checkNoRemainingFields(Map<?, ?> fieldNodeMap, Version indexVersionCreated, String message) {
        if (!fieldNodeMap.isEmpty()) {
            fieldNodeMap.keySet().removeIf(DocumentMapperParser::isElassandraCqlField);
            if (!fieldNodeMap.isEmpty()) {
                throw new MapperParsingException(message + getRemainingFields(fieldNodeMap));
            }
        }
    }

    private static boolean isElassandraCqlField(Object key) {
        return key != null && key.toString().startsWith("cql_");
    }

"""
        if needle not in t:
            print("DocumentMapperParser.java: checkNoRemainingFields anchor not found (for Elassandra CQL compatibility)", file=sys.stderr)
            sys.exit(1)
        t = t.replace(needle, repl, 1)
    write_if_changed(DMP, t)

OM = root / "server/src/main/java/org/opensearch/index/mapper/ObjectMapper.java"
if OM.exists():
    t = OM.read_text(encoding="utf-8")
    if "implements Cloneable, CqlMapper" not in t:
        t = t.replace(
            "public class ObjectMapper extends Mapper implements Cloneable {",
            "public class ObjectMapper extends Mapper implements Cloneable, CqlMapper {",
            1,
        )
    if "public static final CqlMapper.CqlCollection CQL_COLLECTION" not in t:
        needle = """    public static class Defaults {
        public static final boolean ENABLED = true;
        public static final Nested NESTED = Nested.NO;
        public static final Dynamic DYNAMIC = null; // not set, inherited from root
    }
"""
        repl = """    public static class Defaults {
        public static final boolean ENABLED = true;
        public static final Nested NESTED = Nested.NO;
        public static final Dynamic DYNAMIC = null; // not set, inherited from root

        /** Elassandra CQL defaults (fork parity). */
        public static final CqlMapper.CqlCollection CQL_COLLECTION = CqlMapper.CqlCollection.LIST;

        public static final CqlMapper.CqlStruct CQL_STRUCT = CqlMapper.CqlStruct.UDT;
        public static final boolean CQL_MANDATORY = true;
        public static final boolean CQL_PARTITION_KEY = false;
        public static final boolean CQL_STATIC_COLUMN = false;
        public static final boolean CQL_CLUSTERING_KEY_DESC = false;
        public static final int CQL_PRIMARY_KEY_ORDER = -1;
    }
"""
        if needle not in t:
            print("ObjectMapper.java: Defaults anchor not found (for Elassandra CQL defaults)", file=sys.stderr)
            sys.exit(1)
        t = t.replace(needle, repl, 1)
    if "public boolean hasField()" not in t:
        needle = """    public boolean isEnabled() {
        return this.enabled.value();
    }

    public Mapper getMapper(String field) {
        return mappers.get(field);
    }
"""
        repl = """    public boolean isEnabled() {
        return this.enabled.value();
    }

    @Override
    public boolean hasField() {
        for (Mapper mapper : mappers.values()) {
            if (mapper.hasField()) {
                return true;
            }
        }
        return false;
    }

    public Mapper getMapper(String field) {
        return mappers.get(field);
    }
"""
        if needle not in t:
            print("ObjectMapper.java: hasField anchor not found", file=sys.stderr)
            sys.exit(1)
        t = t.replace(needle, repl, 1)
    write_if_changed(OM, t)

FM = root / "server/src/main/java/org/opensearch/index/mapper/FieldMapper.java"
if FM.exists():
    t = FM.read_text(encoding="utf-8")
    if "implements Cloneable, CqlMapper" not in t:
        t = t.replace(
            "public abstract class FieldMapper extends Mapper implements Cloneable {",
            "public abstract class FieldMapper extends Mapper implements Cloneable, CqlMapper {",
            1,
        )
    if "Elassandra CQL column type" not in t and "Elassandra CQL metadata helpers." not in t:
        needle = """        public List<String> copyToFields() {
            return copyToFields;
        }
    }

}
"""
        repl = """        public List<String> copyToFields() {
            return copyToFields;
        }
    }

    /** Elassandra CQL column type for leaf fields (fork parity; side-car stub). */
    public org.apache.cassandra.cql3.CQL3Type.Raw rawType() {
        return org.apache.cassandra.cql3.CQL3Type.Raw.from(org.apache.cassandra.cql3.CQL3Type.Native.TEXT);
    }

}
"""
        if needle not in t:
            print("FieldMapper.java: tail anchor not found", file=sys.stderr)
            sys.exit(1)
        t = t.replace(needle, repl, 1)
    write_if_changed(FM, t)

RF = root / "server/src/main/java/org/opensearch/index/mapper/RangeFieldMapper.java"
if RF.exists():
    t = RF.read_text(encoding="utf-8")
    stub = """    /** Elassandra CQL UDT field layout for range types (fork parity; side-car stub). */
    public java.util.Map<String, org.apache.cassandra.cql3.CQL3Type.Raw> cqlFieldTypes() {
        return java.util.Collections.emptyMap();
    }
"""
    real = """    /** Elassandra CQL UDT field layout for range types (fork parity; side-car compat). */
    public java.util.Map<String, org.apache.cassandra.cql3.CQL3Type.Raw> cqlFieldTypes() {
        final org.apache.cassandra.cql3.CQL3Type.Raw valueType;
        switch (fieldType().typeName()) {
            case "date_range":
            case "long_range":
                valueType = org.apache.cassandra.cql3.CQL3Type.Raw.from(org.apache.cassandra.cql3.CQL3Type.Native.BIGINT);
                break;
            case "ip_range":
                valueType = org.apache.cassandra.cql3.CQL3Type.Raw.from(org.apache.cassandra.cql3.CQL3Type.Native.INET);
                break;
            case "integer_range":
                valueType = org.apache.cassandra.cql3.CQL3Type.Raw.from(org.apache.cassandra.cql3.CQL3Type.Native.INT);
                break;
            case "float_range":
                valueType = org.apache.cassandra.cql3.CQL3Type.Raw.from(org.apache.cassandra.cql3.CQL3Type.Native.FLOAT);
                break;
            case "double_range":
                valueType = org.apache.cassandra.cql3.CQL3Type.Raw.from(org.apache.cassandra.cql3.CQL3Type.Native.DOUBLE);
                break;
            default:
                throw new IllegalStateException("Unsupported range type [" + fieldType().typeName() + "]");
        }
        java.util.LinkedHashMap<String, org.apache.cassandra.cql3.CQL3Type.Raw> fields = new java.util.LinkedHashMap<>();
        fields.put(org.opensearch.index.query.RangeQueryBuilder.FROM_FIELD.getPreferredName(), valueType);
        fields.put(org.opensearch.index.query.RangeQueryBuilder.TO_FIELD.getPreferredName(), valueType);
        fields.put("include_lower", org.apache.cassandra.cql3.CQL3Type.Raw.from(org.apache.cassandra.cql3.CQL3Type.Native.BOOLEAN));
        fields.put("include_upper", org.apache.cassandra.cql3.CQL3Type.Raw.from(org.apache.cassandra.cql3.CQL3Type.Native.BOOLEAN));
        return fields;
    }
"""
    if stub in t:
        t = t.replace(stub, real, 1)
    elif "Elassandra CQL UDT field layout" not in t:
        needle = """        @Override
        public BytesRef binaryValue() {
            try {
                return rangeType.encodeRanges(ranges);
            } catch (IOException e) {
                throw new OpenSearchException("failed to encode ranges", e);
            }
        }
    }
}
"""
        repl = """        @Override
        public BytesRef binaryValue() {
            try {
                return rangeType.encodeRanges(ranges);
            } catch (IOException e) {
                throw new OpenSearchException("failed to encode ranges", e);
            }
        }
    }

""" + real + """
}
"""
        if needle not in t:
            print("RangeFieldMapper.java: tail anchor not found", file=sys.stderr)
            sys.exit(1)
        t = t.replace(needle, repl, 1)
    write_if_changed(RF, t)

ML = root / "server/src/main/java/org/opensearch/index/mapper/MappingLookup.java"
if ML.exists():
    t = ML.read_text(encoding="utf-8")
    if "smartNameFieldMapper" not in t:
        needle = """    private static String parentObject(String field) {
        int lastDot = field.lastIndexOf('.');
        if (lastDot == -1) {
            return null;
        }
        return field.substring(0, lastDot);
    }
}
"""
        repl = """    private static String parentObject(String field) {
        int lastDot = field.lastIndexOf('.');
        if (lastDot == -1) {
            return null;
        }
        return field.substring(0, lastDot);
    }

    /**
     * Elassandra compatibility ({@code DocumentFieldMappers#smartNameFieldMapper} from ES 6).
     */
    public FieldMapper smartNameFieldMapper(String name) {
        Mapper m = getMapper(name);
        return m instanceof FieldMapper ? (FieldMapper) m : null;
    }
}
"""
        if needle not in t:
            print("MappingLookup.java: tail anchor not found", file=sys.stderr)
            sys.exit(1)
        t = t.replace(needle, repl, 1)
    write_if_changed(ML, t)

MSRV = root / "server/src/main/java/org/opensearch/index/mapper/MapperService.java"
if MSRV.exists():
    t = MSRV.read_text(encoding="utf-8")
    if "ObjectMapper.DEFAULT_KEY" in t:
        t = t.replace("ObjectMapper.DEFAULT_KEY", '"_key"')
    if "public static String DISCOVER = \"discover\";" not in t:
        extra_imports = [
            ("import com.carrotsearch.hppc.cursors.ObjectCursor;\n", "import com.carrotsearch.hppc.cursors.ObjectCursor;\nimport com.google.common.collect.Iterables;\nimport com.google.common.collect.Maps;\n"),
            ("import org.apache.logging.log4j.message.ParameterizedMessage;\n", """import org.apache.logging.log4j.message.ParameterizedMessage;
import org.apache.cassandra.cql3.CQL3Type;
import org.apache.cassandra.cql3.CQLFragmentParser;
import org.apache.cassandra.cql3.ColumnIdentifier;
import org.apache.cassandra.cql3.CqlParser;
import org.apache.cassandra.cql3.QueryProcessor;
import org.apache.cassandra.cql3.UntypedResultSet;
import org.apache.cassandra.cql3.UntypedResultSet.Row;
import org.apache.cassandra.db.marshal.AbstractType;
import org.apache.cassandra.db.marshal.ListType;
import org.apache.cassandra.db.marshal.MapType;
import org.apache.cassandra.db.marshal.SetType;
import org.apache.cassandra.db.marshal.UserType;
import org.apache.cassandra.exceptions.ConfigurationException;
import org.apache.cassandra.exceptions.SyntaxException;
import org.apache.cassandra.schema.ColumnMetadata;
import org.apache.cassandra.schema.KeyspaceMetadata;
import org.apache.cassandra.schema.Schema;
import org.apache.cassandra.schema.TableMetadata;
import org.elassandra.cluster.SchemaManager;
import org.elassandra.index.ElasticSecondaryIndex;
"""),
            ("import java.util.function.Supplier;\n", "import java.util.function.Supplier;\nimport java.util.regex.Pattern;\n"),
        ]
        for needle, repl in extra_imports:
            if needle in t and repl not in t:
                t = t.replace(needle, repl, 1)

        anchor = """    public String keyspace() {
        return getIndexMetadata().keyspace();
    }

    /** Elassandra: legacy per-type mapping names (single-type indices use {@link #SINGLE_MAPPING_NAME}). */
"""
        alt_anchor = """    public String keyspace() {
        return getIndexMetadata().keyspace();
    }

    /** Fork named this getIndexMetaData; OpenSearch uses getIndexMetadata. */
    public org.opensearch.cluster.metadata.IndexMetadata getIndexMetadata() {
        return indexSettings.getIndexMetadata();
    }

    public boolean isMetadataField(String field) {"""
        insert = """    public String keyspace() {
        return getIndexMetadata().keyspace();
    }

    public void buildNativeOrUdtMapping(Map<String, Object> mapping, final AbstractType<?> type) throws IOException {
        CQL3Type cql3type = type.asCQL3Type();
        if (cql3type instanceof CQL3Type.Native) {
            String esType = SchemaManager.cqlMapping.get(cql3type.toString());
            if (esType != null) {
                mapping.put("type", esType);
            } else {
                logger.error("CQL type " + cql3type.toString() + " not supported");
                throw new IOException("CQL type " + cql3type.toString() + " not supported");
            }
        } else if (cql3type instanceof CQL3Type.UserDefined) {
            UserType userType = (UserType) type;
            mapping.put("type", ObjectMapper.NESTED_CONTENT_TYPE);
            mapping.put(TypeParsers.CQL_STRUCT, "udt");
            mapping.put(TypeParsers.CQL_UDT_NAME, userType.getNameAsString());
            Map<String, Object> properties = Maps.newHashMap();
            for (int i = 0; i < userType.size(); i++) {
                Map<String, Object> fieldProps = Maps.newHashMap();
                buildCollectionMapping(fieldProps, userType.type(i));
                properties.put(userType.fieldNameAsString(i), fieldProps);
            }
            mapping.put("properties", properties);
        }
    }

    private void buildCollectionMapping(Map<String, Object> mapping, final AbstractType<?> type) throws IOException {
        if (type.isCollection()) {
            if (type instanceof ListType) {
                mapping.put(TypeParsers.CQL_COLLECTION, "list");
                buildNativeOrUdtMapping(mapping, ((ListType<?>) type).getElementsType());
            } else if (type instanceof SetType) {
                mapping.put(TypeParsers.CQL_COLLECTION, "set");
                buildNativeOrUdtMapping(mapping, ((SetType<?>) type).getElementsType());
            } else if (type instanceof MapType) {
                MapType<?, ?> mtype = (MapType<?, ?>) type;
                if (mtype.getKeysType().asCQL3Type() == CQL3Type.Native.TEXT && (mtype.getValuesType().isUDT() || !mtype.getValuesType().isCollection())) {
                    mapping.put(TypeParsers.CQL_COLLECTION, "singleton");
                    mapping.put(TypeParsers.CQL_STRUCT, "opaque_map");
                    mapping.put(TypeParsers.CQL_MANDATORY, Boolean.TRUE);
                    mapping.put("type", ObjectMapper.NESTED_CONTENT_TYPE);

                    Map<String, Object> properties = Maps.newHashMap();
                    Map<String, Object> fieldProps = Maps.newHashMap();
                    buildCollectionMapping(fieldProps, mtype.getValuesType());
                    properties.put("_key", fieldProps);
                    mapping.put("properties", properties);
                } else {
                    throw new IOException("Expecting a map<text,?>");
                }
            }
        } else {
            mapping.put(TypeParsers.CQL_COLLECTION, "singleton");
            buildNativeOrUdtMapping(mapping, type);
        }
    }

    /**
     * Mapping property to discover mapping from CQL schema for columns matching the provided regular expression.
     */
    public static String DISCOVER = "discover";

    public Map<String, Object> discoverTableMapping(final String type, Map<String, Object> mapping)
        throws IOException, SyntaxException, ConfigurationException {
        final String columnRegexp = (String) mapping.get(DISCOVER);
        final String cfName = SchemaManager.typeToCfName(keyspace(), type);
        if (columnRegexp != null) {
            mapping.remove(DISCOVER);
            Pattern pattern = Pattern.compile(columnRegexp);
            Map<String, Object> properties = (Map<String, Object>) mapping.get("properties");
            if (properties == null) {
                properties = Maps.newHashMap();
                mapping.put("properties", properties);
            }
            String ksName = keyspace();
            KeyspaceMetadata ksm = Schema.instance.getKeyspaceMetadata(ksName);
            try {
                TableMetadata metadata = SchemaManager.getTableMetadata(ksName, cfName);
                List<String> pkColNames = new ArrayList<String>(metadata.partitionKeyColumns().size() + metadata.clusteringColumns().size());
                for (ColumnMetadata cd : Iterables.concat(metadata.partitionKeyColumns(), metadata.clusteringColumns())) {
                    pkColNames.add(cd.name.toString());
                }

                UntypedResultSet result = QueryProcessor.executeOnceInternal(
                    "SELECT column_name, type FROM system_schema.columns WHERE keyspace_name=? and table_name=?",
                    new Object[] { keyspace(), cfName }
                );
                for (Row row : result) {
                    String columnName = row.getString("column_name");
                    if (row.has("type")
                        && pattern.matcher(columnName).matches()
                        && columnName.startsWith("_") == false
                        && ElasticSecondaryIndex.ES_QUERY.equals(columnName) == false
                        && ElasticSecondaryIndex.ES_OPTIONS.equals(columnName) == false) {
                        Map<String, Object> props = (Map<String, Object>) properties.get(columnName);
                        if (props == null) {
                            props = Maps.newHashMap();
                            properties.put(columnName, props);
                        }
                        int pkOrder = pkColNames.indexOf(columnName);
                        if (pkOrder >= 0) {
                            props.put(TypeParsers.CQL_PRIMARY_KEY_ORDER, pkOrder);
                            if (pkOrder < metadata.partitionKeyColumns().size()) {
                                props.put(TypeParsers.CQL_PARTITION_KEY, true);
                            }
                        }
                        ColumnMetadata colDef = metadata.getColumn(new ColumnIdentifier(columnName, true));
                        if (colDef.isStatic()) {
                            props.put(TypeParsers.CQL_STATIC_COLUMN, true);
                        }
                        if (colDef.clusteringOrder() == ColumnMetadata.ClusteringOrder.DESC) {
                            props.put(TypeParsers.CQL_CLUSTERING_KEY_DESC, true);
                        }
                        CQL3Type.Raw rawType = CQLFragmentParser.parseAny(CqlParser::comparatorType, row.getString("type"), "CQL type");
                        AbstractType<?> atype = rawType.prepare(ksm.name, ksm.types).getType();
                        buildCollectionMapping(props, atype);
                    }
                }
                if (logger.isDebugEnabled()) {
                    logger.debug("mapping {} : {}", cfName, mapping);
                }
                return mapping;
            } catch (IOException | SyntaxException | ConfigurationException e) {
                logger.warn("Failed to build elasticsearch mapping " + ksName + "." + cfName, e);
                throw e;
            }
        }
        return mapping;
    }

    /** Elassandra: legacy per-type mapping names (single-type indices use {@link #SINGLE_MAPPING_NAME}). */
"""
        alt_insert = insert + """    /** Fork named this getIndexMetaData; OpenSearch uses getIndexMetadata. */
    public org.opensearch.cluster.metadata.IndexMetadata getIndexMetadata() {
        return indexSettings.getIndexMetadata();
    }

    public boolean isMetadataField(String field) {"""
        if anchor in t:
            t = t.replace(anchor, insert, 1)
        elif alt_anchor in t:
            t = t.replace(alt_anchor, alt_insert, 1)
        else:
            print("MapperService.java: keyspace anchor not found (for discover mapping support)", file=sys.stderr)
            sys.exit(1)
    write_if_changed(MSRV, t)

DMP = root / "server/src/main/java/org/opensearch/index/mapper/DocumentMapperParser.java"
if DMP.exists():
    t = DMP.read_text(encoding="utf-8")
    if "import org.opensearch.common.logging.Loggers;\n" in t:
        t = t.replace("import org.opensearch.common.logging.Loggers;\n", "import org.apache.logging.log4j.LogManager;\n")
    if "Loggers.getLogger(DocumentMapperParser.class)" in t:
        t = t.replace("Loggers.getLogger(DocumentMapperParser.class)", "LogManager.getLogger(DocumentMapperParser.class)")
    if "discoverTableMapping(mapping.v1(), mapping.v2())" not in t:
        import_anchors = [
            ("import org.opensearch.Version;\n", "import org.opensearch.Version;\nimport org.apache.cassandra.exceptions.ConfigurationException;\nimport org.apache.cassandra.exceptions.SyntaxException;\nimport org.apache.logging.log4j.Logger;\n"),
            ("import org.opensearch.common.compress.CompressedXContent;\n", "import org.opensearch.common.compress.CompressedXContent;\nimport org.apache.logging.log4j.LogManager;\n"),
            ("import java.util.HashMap;\n", "import java.io.IOException;\nimport java.util.HashMap;\n"),
        ]
        for needle, repl in import_anchors:
            if needle in t and repl not in t:
                t = t.replace(needle, repl, 1)

        logger_anchor = """    private final Supplier<QueryShardContext> queryShardContextSupplier;

    private final RootObjectMapper.TypeParser rootObjectTypeParser = new RootObjectMapper.TypeParser();
"""
        logger_insert = """    private final Supplier<QueryShardContext> queryShardContextSupplier;
    private static final Logger logger = LogManager.getLogger(DocumentMapperParser.class);

    private final RootObjectMapper.TypeParser rootObjectTypeParser = new RootObjectMapper.TypeParser();
"""
        if logger_anchor not in t:
            print("DocumentMapperParser.java: logger anchor not found", file=sys.stderr)
            sys.exit(1)
        t = t.replace(logger_anchor, logger_insert, 1)

        old_tail = """        if (type == null || type.equals(rootName) || mapperService.resolveDocumentType(type).equals(rootName)) {
            mapping = new Tuple<>(rootName, (Map<String, Object>) root.get(rootName));
        } else {
            mapping = new Tuple<>(type, root);
        }
        return mapping;
"""
        new_tail = """        if (type == null || type.equals(rootName) || mapperService.resolveDocumentType(type).equals(rootName)) {
            mapping = new Tuple<>(rootName, (Map<String, Object>) root.get(rootName));
        } else {
            mapping = new Tuple<>(type, root);
        }

        try {
            this.mapperService.discoverTableMapping(mapping.v1(), mapping.v2());
        } catch (SyntaxException | ConfigurationException | IOException e) {
            logger.error("Failed to expand mapping", e);
        }
        return mapping;
"""
        if old_tail not in t:
            print("DocumentMapperParser.java: extractMapping tail anchor not found", file=sys.stderr)
            sys.exit(1)
        t = t.replace(old_tail, new_tail, 1)
    write_if_changed(DMP, t)

PFM = root / "server/src/main/java/org/opensearch/index/mapper/ParametrizedFieldMapper.java"
if PFM.exists():
    t = PFM.read_text(encoding="utf-8")
    if 'if (parameter == null && propName.startsWith("cql_")) {' not in t:
        needle = """                } else {
                    parameter = paramsMap.get(propName);
                }
                if (parameter == null) {
"""
        repl = """                } else {
                    parameter = paramsMap.get(propName);
                }
                if (parameter == null && propName.startsWith("cql_")) {
                    iterator.remove();
                    continue;
                }
                if (parameter == null) {
"""
        if needle not in t:
            print("ParametrizedFieldMapper.java: cql_* ignore anchor not found", file=sys.stderr)
            sys.exit(1)
        t = t.replace(needle, repl, 1)
    write_if_changed(PFM, t)

# Stock OpenSearch tests that construct ObjectMapper directly need the Elassandra CQL constructor args.
FAV = root / "server/src/test/java/org/opensearch/index/mapper/FieldAliasMapperValidationTests.java"
if FAV.exists():
    t = FAV.read_text(encoding="utf-8")
    if "ObjectMapper.Defaults.CQL_PRIMARY_KEY_ORDER" not in t:
        old1 = """    private static ObjectMapper createObjectMapper(String name) {
        return new ObjectMapper(
            name,
            name,
            new Explicit<>(true, false),
            ObjectMapper.Nested.NO,
            ObjectMapper.Dynamic.FALSE,
            emptyMap(),
            Settings.EMPTY
        );
    }"""
        new1 = """    private static ObjectMapper createObjectMapper(String name) {
        return new ObjectMapper(
            name,
            name,
            new Explicit<>(true, false),
            ObjectMapper.Nested.NO,
            ObjectMapper.Dynamic.FALSE,
            ObjectMapper.Defaults.CQL_COLLECTION,
            ObjectMapper.Defaults.CQL_STRUCT,
            null,
            ObjectMapper.Defaults.CQL_MANDATORY,
            ObjectMapper.Defaults.CQL_PARTITION_KEY,
            ObjectMapper.Defaults.CQL_STATIC_COLUMN,
            ObjectMapper.Defaults.CQL_CLUSTERING_KEY_DESC,
            ObjectMapper.Defaults.CQL_PRIMARY_KEY_ORDER,
            emptyMap(),
            Settings.EMPTY
        );
    }"""
        old2 = """    private static ObjectMapper createNestedObjectMapper(String name) {
        return new ObjectMapper(
            name,
            name,
            new Explicit<>(true, false),
            ObjectMapper.Nested.newNested(),
            ObjectMapper.Dynamic.FALSE,
            emptyMap(),
            Settings.EMPTY
        );
    }"""
        new2 = """    private static ObjectMapper createNestedObjectMapper(String name) {
        return new ObjectMapper(
            name,
            name,
            new Explicit<>(true, false),
            ObjectMapper.Nested.newNested(),
            ObjectMapper.Dynamic.FALSE,
            ObjectMapper.Defaults.CQL_COLLECTION,
            ObjectMapper.Defaults.CQL_STRUCT,
            null,
            ObjectMapper.Defaults.CQL_MANDATORY,
            ObjectMapper.Defaults.CQL_PARTITION_KEY,
            ObjectMapper.Defaults.CQL_STATIC_COLUMN,
            ObjectMapper.Defaults.CQL_CLUSTERING_KEY_DESC,
            ObjectMapper.Defaults.CQL_PRIMARY_KEY_ORDER,
            emptyMap(),
            Settings.EMPTY
        );
    }"""
        if old1 in t and old2 in t:
            t = t.replace(old1, new1, 1).replace(old2, new2, 1)
            write_if_changed(FAV, t)
        elif "createObjectMapper(String name)" in t:
            print(
                "FieldAliasMapperValidationTests.java: expected stock ObjectMapper(...) helpers; manual update needed",
                file=sys.stderr,
            )
PY

chmod +x /Users/maxsmith/Documents/GitHub/elassandra/scripts/patch-opensearch-mappers-elassandra-cql-compat.sh 2>/dev/null || true

echo "OpenSearch mapper Elassandra CQL compat OK → $DEST"
