#!/usr/bin/env bash
# Restore Elassandra DateFieldMapper CQL conversions in the OpenSearch sidecar.
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
FILE="$DEST/server/src/main/java/org/opensearch/index/mapper/DateFieldMapper.java"
[[ -f "$FILE" ]] || exit 0

python3 - "$FILE" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

parse_block = """        protected DateMathParser dateMathParser() {
            return dateMathParser;
        }

        private boolean isTimeuuid() {
            String cqlType = meta().get(TypeParsers.CQL_TYPE);
            return cqlType != null && "timeuuid".equalsIgnoreCase(cqlType);
        }

        // Visible for testing.
        public long parse(String value) {
            if (isTimeuuid()) {
                return resolution.convert(Instant.ofEpochMilli(org.apache.cassandra.utils.UUIDGen.unixTimestamp(java.util.UUID.fromString(value))));
            }
            return resolution.convert(DateFormatters.from(dateTimeFormatter().parse(value), dateTimeFormatter().locale()).toInstant());
        }
"""

parse_block_pattern = re.compile(
    r"""        protected DateMathParser dateMathParser\(\) \{
            return dateMathParser;
        \}

        // Visible for testing\.
        public long parse\(String value\) \{
.*?
        \}
""",
    re.S,
)
if "private boolean isTimeuuid()" not in text:
    if not parse_block_pattern.search(text):
        print(f"DateFieldMapper parse(String) anchor missing: {path}", file=sys.stderr)
        sys.exit(1)
    text = parse_block_pattern.sub(parse_block, text, count=1)

value_block = """        @Override
        public Object valueForDisplay(Object value) {
            if (value == null) {
                return null;
            }
            if (value instanceof java.util.Date) {
                return dateTimeFormatter().format(((java.util.Date) value).toInstant().atZone(ZoneOffset.UTC));
            }
            if (value instanceof Long) {
                Long val = (Long) value;
                return dateTimeFormatter().format(resolution.toInstant(val).atZone(ZoneOffset.UTC));
            }
            return value;
        }

        @Override
        public Object cqlValue(Object value, org.apache.cassandra.db.marshal.AbstractType<?> atype) {
            Object val = cqlValue(value);
            if (val instanceof java.util.Date && atype instanceof org.apache.cassandra.db.marshal.SimpleDateType) {
                return org.apache.cassandra.serializers.SimpleDateSerializer.timeInMillisToDay(((java.util.Date) val).getTime());
            }
            return val;
        }

        @Override
        public Object cqlValue(Object value) {
            if (value == null) {
                return null;
            }
            if (isTimeuuid()) {
                return value instanceof java.util.UUID ? value : java.util.UUID.fromString(value.toString());
            }
            if (value instanceof java.util.Date) {
                return value;
            }
            if (value instanceof Number) {
                return new java.util.Date(((Number) value).longValue());
            }
            if (value instanceof org.apache.lucene.util.BytesRef) {
                return new java.util.Date(org.opensearch.common.Numbers.bytesToLong((org.apache.lucene.util.BytesRef) value));
            }
            return java.util.Date.from(resolution.toInstant(parse(value.toString())));
        }
"""

value_block_pattern = re.compile(
    r"""        @Override
        public Object valueForDisplay\(Object value\) \{
.*?
        @Override
        public DocValueFormat docValueFormat\(@Nullable String format, ZoneId timeZone\) \{""",
    re.S,
)
if not value_block_pattern.search(text):
    print(f"DateFieldMapper value/docValueFormat anchor missing: {path}", file=sys.stderr)
    sys.exit(1)
text = value_block_pattern.sub(
    value_block + """

        @Override
        public DocValueFormat docValueFormat(@Nullable String format, ZoneId timeZone) {""",
    text,
    count=1,
)

external_value_block = """        if (context.externalValueSet()) {
            Object dateAsObject = context.externalValue();
            if (dateAsObject == null) {
                dateAsString = null;
            } else if (dateAsObject instanceof java.util.Date) {
                dateAsString = Long.toString(((java.util.Date) dateAsObject).getTime());
            } else if (dateAsObject instanceof Number) {
                dateAsString = dateAsObject.toString();
            } else if (dateAsObject instanceof org.apache.lucene.util.BytesRef) {
                dateAsString = Long.toString(org.opensearch.common.Numbers.bytesToLong((org.apache.lucene.util.BytesRef) dateAsObject));
            } else {
                dateAsString = dateAsObject.toString();
            }
        } else {
"""

external_value_pattern = re.compile(
    r"""        if \(context\.externalValueSet\(\)\) \{
            Object dateAsObject = context\.externalValue\(\);
.*?
        \} else \{""",
    re.S,
)
if not external_value_pattern.search(text):
    print(f"DateFieldMapper parseCreateField anchor missing: {path}", file=sys.stderr)
    sys.exit(1)
text = external_value_pattern.sub(external_value_block, text, count=1)

if text.count("public Object cqlValue(Object value, org.apache.cassandra.db.marshal.AbstractType<?> atype)") != 1:
    print(f"DateFieldMapper cqlValue(Object, AbstractType) count mismatch: {path}", file=sys.stderr)
    sys.exit(1)
if text.count("public Object cqlValue(Object value)") != 1:
    print(f"DateFieldMapper cqlValue(Object) count mismatch: {path}", file=sys.stderr)
    sys.exit(1)

path.write_text(text, encoding="utf-8")
print(f"Patched DateFieldMapper cqlValue: {path}")
PY
