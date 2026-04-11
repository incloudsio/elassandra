#!/usr/bin/env bash
# OpenSearch tests install PathUtils.DEFAULT = Lucene mock FS; path.data under cassandra.home/data/elasticsearch.data is outside that tree → NodeEnvironment mkdir failures (SKIPPED, worker exit 100).
# Pass one Lucene createTempDir() root into initElassandraDeamon(..., opensearchDataPath); use a static singleton path (no nested elasticsearch.data / no extra createTempDir per ctor) so the mock FS does not hit FileAlreadyExists on nodes/0.
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
F="$DEST/test/framework/src/main/java/org/opensearch/test/OpenSearchSingleNodeTestCase.java"
[[ -f "$F" ]] || exit 0

python3 - "$F" <<'PY'
import pathlib, re, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
changed = False

def uses_embedded_data_path(t: str) -> bool:
    return (
        '.put(Environment.PATH_DATA_SETTING.getKey(), opensearchDataPath)' in t
        or '.put(Environment.PATH_DATA_SETTING.getKey(), resolvedOpensearchDataPath)' in t
    )

# Remove stale "resolvedOpensearchDataPath" helper — nodeSettings must use the init parameter `opensearchDataPath`.
if "final String resolvedOpensearchDataPath" in text:
    text = re.sub(
        r"\n            final String resolvedOpensearchDataPath =[\s\S]*?DatabaseDescriptor\.getAllDataFileLocations\(\)\[0\] \+ File\.separatorChar \+ \"elasticsearch\.data\";\n",
        "\n",
        text,
        count=1,
    )
    text = text.replace(
        "resolvedOpensearchDataPath",
        "opensearchDataPath",
    )
    changed = True

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
sig_pat = r"    public static synchronized void initElassandraDeamon\(Settings testSettings, Collection<Class<\? extends Plugin>> classpathPlugins\)\s*\{\n"
if re.search(sig_pat, text):
    text = re.sub(sig_pat, new_sig, text, count=1)
    changed = True

# ESSingleNode uses PATH_REPO with `+"/repo"` (no spaces); older patch scripts expected `+ "/repo"`. Match DATA lines only.
dd_path = (
    r'DatabaseDescriptor\.getAllDataFileLocations\(\)\[0\] \+ File\.separatorChar \+ "elasticsearch\.data"'
)
for setting in ("PATH_DATA_SETTING", "PATH_SHARED_DATA_SETTING"):
    pat = re.compile(
        r'(\s+\.put\(Environment\.' + setting + r'\.getKey\(\), )' + dd_path + r'(\)\s*\n)'
    )
    new_t, n = pat.subn(r'\1opensearchDataPath\2', text, count=1)
    if n:
        text = new_t
        changed = True

# After prepare, nodeSettings may already use opensearchDataPath; ensure bootstrap natives match embedded tests.
boot_snip = '                        .put("bootstrap.memory_lock", false)\n                        .put("bootstrap.system_call_filter", false)\n                        .put("discovery.type", MockCassandraDiscovery.MOCK_CASSANDRA)'
if "opensearchDataPath" in text and "bootstrap.memory_lock" not in text and '                        .put("discovery.type", MockCassandraDiscovery.MOCK_CASSANDRA)' in text:
    text = text.replace(
        '                        .put("discovery.type", MockCassandraDiscovery.MOCK_CASSANDRA)',
        boot_snip,
        1,
    )
    changed = True

old_ctor = "        initElassandraDeamon(nodeSettings(1), getPlugins());\n"
new_ctor = (
    "        if (embeddedOpensearchDataPath == null) {\n"
    "            synchronized (OpenSearchSingleNodeTestCase.class) {\n"
    "                if (embeddedOpensearchDataPath == null) {\n"
    "                    // Unique leaf: ctor thread vs suite worker can otherwise share tempDir-001 (FileAlreadyExists).\n"
    "                    embeddedOpensearchDataPath =\n"
    "                        createTempDir(\"elassandra-embedded-os-\" + java.util.UUID.randomUUID().toString().replace(\"-\", \"\"))\n"
    "                            .toAbsolutePath()\n"
    "                            .toString();\n"
    "                }\n"
    "            }\n"
    "        }\n"
    "        initElassandraDeamon(nodeSettings(1), getPlugins(), embeddedOpensearchDataPath);\n"
)
has_field = (
    "private static volatile String embeddedOpensearchDataPath" in text
    or "private static String embeddedOpensearchDataPath" in text
)
if not has_field:
    needle = "    private static final Semaphore testMutex = new Semaphore(1);\n"
    insert = (
        "    private static final Semaphore testMutex = new Semaphore(1);\n"
        "\n"
        "    /** One OpenSearch data root for the JVM singleton daemon; nested {@code elasticsearch.data} + extra {@link #createTempDir()} calls confused the Lucene mock FS. */\n"
        "    private static volatile String embeddedOpensearchDataPath;\n"
    )
    if needle in text:
        text = text.replace(needle, insert, 1)
        changed = True

if old_ctor in text:
    text = text.replace(old_ctor, new_ctor, 1)
    changed = True

old_ctor2 = (
    "        initElassandraDeamon(\n"
    "            nodeSettings(1),\n"
    "            getPlugins(),\n"
    "            createTempDir().resolve(\"elasticsearch.data\").toAbsolutePath().toString()\n"
    "        );\n"
)
if old_ctor2 in text:
    text = text.replace(old_ctor2, new_ctor, 1)
    changed = True

if changed:
    path.write_text(text, encoding="utf-8")
    print("Patched OpenSearchSingleNodeTestCase (mock-fs opensearch data path) →", path)
elif uses_embedded_data_path(text):
    print("OpenSearchSingleNodeTestCase: mock-fs data path already wired →", path)
else:
    print("OpenSearchSingleNodeTestCase: mock-fs data path anchor not found →", path, file=sys.stderr)
    sys.exit(1)
PY
