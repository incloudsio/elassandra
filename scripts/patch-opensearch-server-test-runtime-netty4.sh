#!/usr/bin/env bash
# ESSingleNodeTestCase registers Netty4Plugin for ElassandraNode HTTP; :server:test classpath needs the module jar.
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
F="$DEST/server/build.gradle"
[[ -f "$F" ]] || exit 0

if grep -q "testRuntimeOnly project(':modules:transport-netty4')" "$F" 2>/dev/null; then
  echo "server/build.gradle: transport-netty4 testRuntimeOnly already present → $F"
  exit 0
fi

python3 - "$F" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
needle = """  internalClusterTestImplementation(project(":test:framework")) {
    exclude group: 'org.opensearch', module: 'server'
  }
}"""
insert = """  internalClusterTestImplementation(project(":test:framework")) {
    exclude group: 'org.opensearch', module: 'server'
  }
  // Embedded Elassandra (ESSingleNodeTestCase) loads Netty4Plugin explicitly; keep it on :server:test runtime classpath.
  testRuntimeOnly project(':modules:transport-netty4')
}"""
if needle not in text:
    print("patch-opensearch-server-test-runtime-netty4: anchor not found →", path, file=sys.stderr)
    sys.exit(1)
path.write_text(text.replace(needle, insert, 1), encoding="utf-8")
print("Patched server/build.gradle (testRuntimeOnly transport-netty4) →", path)
PY
