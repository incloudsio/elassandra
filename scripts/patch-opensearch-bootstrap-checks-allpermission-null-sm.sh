#!/usr/bin/env bash
# With -Dtests.security.manager=false, AllPermissionCheck#isAllPermissionGranted hits "assert sm != null" and fails before returning.
# Embedded Cassandra needs the SM off for netty property writes during DatabaseDescriptor <clinit>.
#
# Usage: ./scripts/patch-opensearch-bootstrap-checks-allpermission-null-sm.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
F="$DEST/server/src/main/java/org/opensearch/bootstrap/BootstrapChecks.java"
[[ -f "$F" ]] || exit 0

if grep -q 'AllPermissionCheck: skip when SecurityManager is null' "$F" 2>/dev/null \
  || grep -q 'Elassandra embedded tests use -Dtests.security.manager=false' "$F" 2>/dev/null; then
  echo "BootstrapChecks AllPermissionCheck null-SM guard already present → $F"
  exit 0
fi

python3 - "$F" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
old = """        boolean isAllPermissionGranted() {
            final SecurityManager sm = System.getSecurityManager();
            assert sm != null;
            try {
                sm.checkPermission(new AllPermission());
            } catch (final SecurityException e) {
                return false;
            }
            return true;
        }"""
new = """        boolean isAllPermissionGranted() {
            final SecurityManager sm = System.getSecurityManager();
            // Elassandra embedded tests use -Dtests.security.manager=false so Cassandra can set Netty properties; treat as not "all permission".
            if (sm == null) {
                return false;
            }
            try {
                sm.checkPermission(new AllPermission());
            } catch (final SecurityException e) {
                return false;
            }
            return true;
        }"""
if old not in text:
    print("BootstrapChecks: AllPermissionCheck.isAllPermissionGranted block not found", file=sys.stderr)
    sys.exit(1)
text = text.replace(old, new, 1)
path.write_text(text, encoding="utf-8")
print("Patched BootstrapChecks AllPermissionCheck (null SecurityManager) →", path)
PY
