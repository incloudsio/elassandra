#!/usr/bin/env bash
# OpenSearch tests install PathUtils.DEFAULT = Lucene mock FS; path.data under cassandra.home/data/elasticsearch.data is outside that tree → NodeEnvironment mkdir failures (SKIPPED, worker exit 100).
# Pass a subdirectory of Lucene createTempDir() into initElassandraDeamon(..., opensearchDataPath).
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
F="$DEST/test/framework/src/main/java/org/opensearch/test/ESSingleNodeTestCase.java"
[[ -f "$F" ]] || exit 0

python3 - "$F" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
changed = False

if "String opensearchDataPath" in text and "createTempDir().resolve(\"elasticsearch.data\")" in text:
    print("ESSingleNodeTestCase: mock-fs data path already applied →", path)
    path.write_text(text, encoding="utf-8")
    sys.exit(0)

old_sig = "    public static synchronized void initElassandraDeamon(Settings testSettings, Collection<Class<? extends Plugin>> classpathPlugins) {\n"
new_sig = (
    "    /**\n"
    "     * @param opensearchDataPath absolute path for OpenSearch {@code path.data} / shared data; must live under Lucene's mock filesystem\n"
    "     *                           (use {@link #createTempDir()}), not under {@code cassandra.home}/data, or {@link org.opensearch.env.NodeEnvironment} fails on the test FS.\n"
    "     */\n"
    "    public static synchronized void initElassandraDeamon(\n"
    "        Settings testSettings,\n"
    "        Collection<Class<? extends Plugin>> classpathPlugins,\n"
    "        String opensearchDataPath\n"
    "    ) {\n"
)
if old_sig in text:
    text = text.replace(old_sig, new_sig, 1)
    changed = True

old_paths = (
    "                        .put(Environment.PATH_DATA_SETTING.getKey(), DatabaseDescriptor.getAllDataFileLocations()[0] + File.separatorChar + \"elasticsearch.data\")\n"
    "                        .put(Environment.PATH_REPO_SETTING.getKey(), System.getProperty(\"cassandra.home\") + \"/repo\")\n"
    "                        .put(Environment.PATH_SHARED_DATA_SETTING.getKey(), DatabaseDescriptor.getAllDataFileLocations()[0] + File.separatorChar + \"elasticsearch.data\")\n"
)
new_paths = (
    "                        .put(Environment.PATH_DATA_SETTING.getKey(), opensearchDataPath)\n"
    "                        .put(Environment.PATH_REPO_SETTING.getKey(), System.getProperty(\"cassandra.home\") + \"/repo\")\n"
    "                        .put(Environment.PATH_SHARED_DATA_SETTING.getKey(), opensearchDataPath)\n"
)
if old_paths in text:
    text = text.replace(old_paths, new_paths, 1)
    changed = True

old_ctor = "        initElassandraDeamon(nodeSettings(1), getPlugins());\n"
new_ctor = (
    "        initElassandraDeamon(\n"
    "            nodeSettings(1),\n"
    "            getPlugins(),\n"
    "            createTempDir().resolve(\"elasticsearch.data\").toAbsolutePath().toString()\n"
    "        );\n"
)
if old_ctor in text:
    text = text.replace(old_ctor, new_ctor, 1)
    changed = True

if changed:
    path.write_text(text, encoding="utf-8")
    print("Patched ESSingleNodeTestCase (mock-fs opensearch data path) →", path)
else:
    if "opensearchDataPath" in text:
        print("ESSingleNodeTestCase: mock-fs data path present; no file change →", path)
    else:
        print("ESSingleNodeTestCase: mock-fs data path anchor not found →", path, file=sys.stderr)
        sys.exit(1)
PY
