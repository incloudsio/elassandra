#!/usr/bin/env bash
# Elassandra side-car :server:test sets cassandra.home and loads Cassandra inside the forked test JVM. The stock
# OpenSearch test SecurityManager policy is too strict (Netty props, JMX, relative conf paths, etc.). When
# tests.security.manager=true, grant java.security.AllPermission when cassandra.home is set (same effective
# freedom as test-framework.policy grants to the Gradle worker jar). Also grant the Gradle test working directory
# so Cassandra can resolve relative paths (e.g. conf/.keystore) against user.dir.
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
F="$DEST/test/framework/src/main/java/org/opensearch/bootstrap/BootstrapForTesting.java"
[[ -f "$F" ]] || exit 0

if grep -q 'Elassandra embedded tests (side-car init.gradle sets cassandra.home)' "$F" 2>/dev/null; then
  echo "BootstrapForTesting Elassandra embedded SM patch already applied → $F"
  exit 0
fi

python3 - "$F" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
needle = (
    "                FilePermissionUtils.addDirectoryPath(perms, \"java.io.tmpdir\", javaTmpDir, \"read,readlink,write,delete\", false);\n"
    "                // custom test config file\n"
)
insert = (
    "                FilePermissionUtils.addDirectoryPath(perms, \"java.io.tmpdir\", javaTmpDir, \"read,readlink,write,delete\", false);\n"
    "                // Gradle test worker cwd (Cassandra sometimes resolves relative paths like conf/.keystore against user.dir).\n"
    "                FilePermissionUtils.addDirectoryPath(\n"
    "                    perms,\n"
    "                    \"user.dir\",\n"
    "                    PathUtils.get(System.getProperty(\"user.dir\")),\n"
    "                    \"read,readlink,write,delete\",\n"
    "                    false\n"
    "                );\n"
    "                // custom test config file\n"
)
if needle not in text:
    print("patch-opensearch-bootstrap-for-testing-elassandra-embedded-sm: expected tmpdir anchor not found →", path, file=sys.stderr)
    sys.exit(1)
text = text.replace(needle, insert, 1)
needle2 = (
    "                    FilePermissionUtils.addSingleFilePath(perms, PathUtils.get(System.getProperty(\"tests.config\")), \"read,readlink\");\n"
    "                }\n"
    "                // intellij hack: intellij test runner wants setIO and will\n"
)
insert2 = (
    "                    FilePermissionUtils.addSingleFilePath(perms, PathUtils.get(System.getProperty(\"tests.config\")), \"read,readlink\");\n"
    "                }\n"
    "                // Elassandra embedded tests (side-car init.gradle sets cassandra.home): Cassandra + Netty + JMX exceed\n"
    "                // the stock OpenSearch test policy; grant AllPermission like the Gradle worker jar (test-framework.policy).\n"
    "                if (Strings.hasLength(System.getProperty(\"cassandra.home\"))) {\n"
    "                    perms.add(new java.security.AllPermission());\n"
    "                }\n"
    "                // intellij hack: intellij test runner wants setIO and will\n"
)
if needle2 not in text:
    print("patch-opensearch-bootstrap-for-testing-elassandra-embedded-sm: expected tests.config anchor not found →", path, file=sys.stderr)
    sys.exit(1)
text = text.replace(needle2, insert2, 1)
path.write_text(text, encoding="utf-8")
print("Patched BootstrapForTesting (Elassandra embedded test SM) →", path)
PY
