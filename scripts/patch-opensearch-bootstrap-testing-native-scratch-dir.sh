#!/usr/bin/env bash
# BootstrapForTesting used to mkdir java.io.tmpdir before Lucene's mock FS → FileAlreadyExists on createDirectory(temp).
# It also must not pass that same path to Bootstrap.initializeNatives on macOS: SystemCallFilter uses Files.createTempFile
# under that directory, which must already exist — use java.io.tmpdir's parent (OpenSearch test workingDir) instead.
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
F="$DEST/test/framework/src/main/java/org/opensearch/bootstrap/BootstrapForTesting.java"
[[ -f "$F" ]] || exit 0

if grep -q 'nativeScratchDir' "$F" 2>/dev/null; then
  echo "BootstrapForTesting nativeScratchDir already patched → $F"
  exit 0
fi

python3 - "$F" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
old = (
    "    static {\n"
    "        // make sure java.io.tmpdir exists always (in case code uses it in a static initializer)\n"
    "        Path javaTmpDir = PathUtils.get(\n"
    "            Objects.requireNonNull(System.getProperty(\"java.io.tmpdir\"), \"please set ${java.io.tmpdir} in pom.xml\")\n"
    "        );\n"
    "        try {\n"
    "            Security.ensureDirectoryExists(javaTmpDir);\n"
    "        } catch (Exception e) {\n"
    "            throw new RuntimeException(\"unable to create test temp directory\", e);\n"
    "        }\n"
    "\n"
    "        // just like bootstrap, initialize natives, then SM\n"
    "        final boolean memoryLock = BootstrapSettings.MEMORY_LOCK_SETTING.get(Settings.EMPTY); // use the default bootstrap.memory_lock\n"
    "                                                                                              // setting\n"
    "        final boolean systemCallFilter = Booleans.parseBoolean(System.getProperty(\"tests.system_call_filter\", \"true\"));\n"
    "        Bootstrap.initializeNatives(javaTmpDir, memoryLock, systemCallFilter, true);\n"
)
new = (
    "    static {\n"
    "        // java.io.tmpdir is created later by Lucene TestRuleTemporaryFilesCleanup (mock FS). Do not mkdir it here:\n"
    "        // pre-creating it caused FileAlreadyExists when Lucene calls createDirectories on the mock layer.\n"
    "        // Natives / macImpl need an existing directory only for Files.createTempFile(dir, ...); use tmpdir's parent\n"
    "        // (OpenSearch: workingDir/test) which Gradle mkdirs in test.doFirst.\n"
    "        Path javaTmpDir = PathUtils.get(\n"
    "            Objects.requireNonNull(System.getProperty(\"java.io.tmpdir\"), \"please set ${java.io.tmpdir} in pom.xml\")\n"
    "        );\n"
    "        Path nativeScratchDir = javaTmpDir.getParent();\n"
    "        if (nativeScratchDir == null) {\n"
    "            nativeScratchDir = javaTmpDir;\n"
    "        }\n"
    "        try {\n"
    "            Security.ensureDirectoryExists(nativeScratchDir);\n"
    "        } catch (Exception e) {\n"
    "            throw new RuntimeException(\"unable to create native scratch directory for tests\", e);\n"
    "        }\n"
    "\n"
    "        // just like bootstrap, initialize natives, then SM\n"
    "        final boolean memoryLock = BootstrapSettings.MEMORY_LOCK_SETTING.get(Settings.EMPTY); // use the default bootstrap.memory_lock\n"
    "                                                                                              // setting\n"
    "        final boolean systemCallFilter = Booleans.parseBoolean(System.getProperty(\"tests.system_call_filter\", \"true\"));\n"
    "        Bootstrap.initializeNatives(nativeScratchDir, memoryLock, systemCallFilter, true);\n"
)
if old not in text:
    print("BootstrapForTesting: expected upstream static block not found; skip →", path, file=sys.stderr)
    sys.exit(0)
path.write_text(text.replace(old, new, 1), encoding="utf-8")
print("Patched BootstrapForTesting (nativeScratchDir for initializeNatives) →", path)
PY
