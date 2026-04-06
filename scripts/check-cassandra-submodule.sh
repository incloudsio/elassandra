#!/usr/bin/env bash
# Verify buildSrc/version.properties "cassandra=" matches server/cassandra/build.xml base.version.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROP_FILE="$ROOT/buildSrc/version.properties"
BUILD_XML="$ROOT/server/cassandra/build.xml"

if [[ ! -f "$BUILD_XML" ]]; then
  echo "skip: server/cassandra/build.xml missing (run: git submodule update --init server/cassandra)" >&2
  exit 0
fi

PROP_VER="$(grep -E '^[[:space:]]*cassandra[[:space:]]*=' "$PROP_FILE" | head -1 | sed 's/.*=[[:space:]]*//' | tr -d '[:space:]')"
XML_VER="$(grep -E 'property name="base\.version"' "$BUILD_XML" | head -1 | sed 's/.*value="\([^"]*\)".*/\1/')"

if [[ -z "$PROP_VER" || -z "$XML_VER" ]]; then
  echo "error: could not parse cassandra version from properties or build.xml" >&2
  exit 1
fi

if [[ "$PROP_VER" != "$XML_VER" ]]; then
  echo "error: version mismatch" >&2
  echo "  buildSrc/version.properties  cassandra = $PROP_VER" >&2
  echo "  server/cassandra/build.xml     base.version = $XML_VER" >&2
  echo "Bump one side or update the submodule commit after changing Cassandra." >&2
  exit 1
fi

echo "OK: Cassandra artifact version matches submodule build.xml ($PROP_VER)"
