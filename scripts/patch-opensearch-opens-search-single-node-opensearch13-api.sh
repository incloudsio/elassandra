#!/usr/bin/env bash
# OpenSearch 1.3 API alignment for Elassandra's merged OpenSearchSingleNodeTestCase (from ES 6.8 fork).
#
# Usage: ./scripts/patch-opensearch-opens-search-single-node-opensearch13-api.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
F="$DEST/test/framework/src/main/java/org/opensearch/test/OpenSearchSingleNodeTestCase.java"
[[ -f "$F" ]] || exit 0

if grep -q 'OpenSearch 1.3 API alignment applied' "$F" 2>/dev/null; then
  echo "OpenSearchSingleNodeTestCase: OS13 API patch already applied → $F"
  exit 0
fi

python3 - "$F" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

text = text.replace(
    "import org.opensearch.test.discovery.MockCassandraDiscovery;\n",
    "import org.elassandra.discovery.MockCassandraDiscovery;\n",
)
text = text.replace("import org.opensearch.test.discovery.TestZenDiscovery;\n", "")

old_prep = """            ElassandraDaemon.instance = new ElassandraDaemon(InternalSettingsPreparer.prepareEnvironment(Settings.builder()
                .put(Environment.PATH_HOME_SETTING.getKey(), System.getProperty("cassandra.home"))
                .build(), null)) {"""
new_prep = """            ElassandraDaemon.instance = new ElassandraDaemon(InternalSettingsPreparer.prepareEnvironment(Settings.builder()
                .put(Environment.PATH_HOME_SETTING.getKey(), System.getProperty("cassandra.home"))
                .build(), java.util.Collections.emptyMap(), null, () -> "127.0.0.1")) {"""
text = text.replace(old_prep, new_prep, 1)

text = text.replace(
    "                        .put(NetworkModule.HTTP_ENABLED.getKey(), false)\n",
    "",
)
text = text.replace(
    "                        .put(Node.NODE_DATA_SETTING.getKey(), true)\n",
    "                        .put(\"node.roles\", \"data\")\n",
)
text = text.replace(
    "                        .put(ScriptService.SCRIPT_MAX_COMPILATIONS_RATE.getKey(), \"1000/1m\")\n",
    "                        .put(ScriptService.SCRIPT_GENERAL_MAX_COMPILATIONS_RATE_SETTING.getKey(), \"use-context\")\n",
)

text = text.replace(
    "client().admin().cluster().prepareState().get().getState().getMetaData()",
    "client().admin().cluster().prepareState().get().getState().metadata()",
)

# ensureNoWarnings is not overridable on OpenSearchTestCase (private)
old_ensure = """
    protected void ensureNoWarnings() throws IOException {
        super.ensureNoWarnings();
    }
"""
text = text.replace(old_ensure, "\n", 1)

text = text.replace(
    """            if (node != null)
                node.stop();
""",
    """            if (node != null)
                node.close();
""",
)

text = text.replace("import org.apache.lucene.util.IOUtils;\n", "import org.opensearch.core.internal.io.IOUtils;\n")

text = text.replace(
    """    public ClusterService clusterService() {
        return ElassandraDaemon.instance.node().clusterService();
    }
""",
    """    public ClusterService clusterService() {
        return ElassandraDaemon.instance.node().injector().getInstance(ClusterService.class);
    }
""",
)

old_ctx = """    protected SearchContext createSearchContext(IndexService indexService) {
        BigArrays bigArrays = indexService.getBigArrays();
        ThreadPool threadPool = indexService.getThreadPool();
        return new TestSearchContext(threadPool, bigArrays, indexService);
    }"""
new_ctx = """    protected SearchContext createSearchContext(IndexService indexService) {
        BigArrays bigArrays = indexService.getBigArrays();
        return new TestSearchContext(bigArrays, indexService);
    }"""
text = text.replace(old_ctx, new_ctx, 1)

text = text.replace("import org.opensearch.threadpool.ThreadPool;\n", "")

text = "/* OpenSearch 1.3 API alignment applied by patch-opensearch-opens-search-single-node-opensearch13-api.sh */\n" + text
path.write_text(text, encoding="utf-8")
print("Patched OpenSearchSingleNodeTestCase (OS 1.3 API) →", path)
PY
