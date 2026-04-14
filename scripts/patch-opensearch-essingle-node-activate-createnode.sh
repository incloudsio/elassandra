#!/usr/bin/env bash
# Embedded tests: activate(..., createNode=true) so ElassandraNode exists; ringReady() must call super.ringReady()
# for activateAndWaitShards. activate(false,false,...) left node=null and caused worker exit 100 / NPE on client().
# Also always load MockNioTransportPlugin: nodeSettings() sets transport.type mock-nio but getMockPlugins omitted the plugin when addMockTransportService() is false.
# Load the geo module plugin too: CassandraDiscoveryTests exercises geo_shape mappings and the sidecar test runtime
# does not auto-discover module plugins when ElassandraNode is built from an explicit plugin list.
# getPlugins() must return getMockPlugins() so activate() receives transport + discovery plugins (was emptyList → mock-nio / http errors).
# After merging env settings, force http.type netty4: prepared env can set http.type to "" which breaks NetworkModule on ElassandraNode (real Node, not MockNode).
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
F="$DEST/test/framework/src/main/java/org/opensearch/test/OpenSearchSingleNodeTestCase.java"
[[ -f "$F" ]] || exit 0

python3 - "$F" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
changed = False

if "createNode must be true" not in text:
    old_ring = (
        "                @Override\n"
        "                public void ringReady() {\n"
        "                    startLatch.countDown();\n"
        "                }\n"
    )
    new_ring = (
        "                @Override\n"
        "                public void ringReady() {\n"
        "                    super.ringReady();\n"
        "                    startLatch.countDown();\n"
        "                }\n"
    )
    if old_ring not in text:
        print("ESSingleNodeTestCase: expected ringReady() block not found; skip activate patch →", path, file=sys.stderr)
    else:
        text = text.replace(old_ring, new_ring, 1)
        changed = True
    for old_act in (
        "ElassandraDaemon.instance.activate(false, false, elassandraSettings, new Environment(elassandraSettings, confPath), classpathPlugins);",
        "ElassandraDaemon.instance.activate(false, false,  elassandraSettings, new Environment(elassandraSettings, confPath), classpathPlugins);",
    ):
        if old_act in text:
            new_act = (
                "            // createNode must be true so ElassandraNode is constructed; parent ringReady runs activateAndWaitShards.\n"
                "            ElassandraDaemon.instance.activate(false, true, elassandraSettings, new Environment(elassandraSettings, confPath), classpathPlugins);"
            )
            text = text.replace(old_act, new_act, 1)
            changed = True
            break

if "nodeSettings() always sets transport.type" not in text:
    old_tp = (
        "        if (addMockTransportService()) {\n"
        "            mocks.add(getTestTransportPlugin());\n"
        "        }\n"
        "\n"
        "        mocks.add(OpenSearchIntegTestCase.TestSeedPlugin.class);\n"
    )
    new_tp = (
        "        if (addMockTransportService()) {\n"
        "            mocks.add(MockTransportService.TestPlugin.class);\n"
        "        }\n"
        "\n"
        "        // nodeSettings() always sets transport.type to getTestTransportType() (mock-nio); the plugin must be on the classpath.\n"
        "        mocks.add(getTestTransportPlugin());\n"
        "        mocks.add(OpenSearchIntegTestCase.TestSeedPlugin.class);\n"
    )
    if old_tp in text:
        text = text.replace(old_tp, new_tp, 1)
        changed = True
    else:
        print("ESSingleNodeTestCase: getMockPlugins transport block not found; skip transport patch →", path, file=sys.stderr)

if "return getMockPlugins()" not in text:
    old_gp = (
        "    protected Collection<Class<? extends Plugin>> getPlugins() {\n"
        "        return Collections.emptyList();\n"
        "    }\n"
    )
    new_gp = (
        "    protected Collection<Class<? extends Plugin>> getPlugins() {\n"
        "        return getMockPlugins();\n"
        "    }\n"
    )
    if old_gp in text:
        text = text.replace(old_gp, new_gp, 1)
        changed = True

if "ElassandraNode uses real Node + Netty module" not in text:
    if "import org.opensearch.common.network.NetworkModule;" not in text:
        old_imp = "import org.opensearch.common.Priority;\nimport org.opensearch.common.settings.Settings;"
        new_imp = (
            "import org.opensearch.common.Priority;\n"
            "import org.opensearch.common.network.NetworkModule;\n"
            "import org.opensearch.common.settings.Settings;"
        )
        if old_imp in text:
            text = text.replace(old_imp, new_imp, 1)
            changed = True
        else:
            print("ESSingleNodeTestCase: import anchor not found; skip NetworkModule import →", path, file=sys.stderr)
    old_http = (
        "                        .put(\"client.type\", \"node\")\n"
        "                        .put(settings)\n"
        "                        .build();\n"
    )
    new_http = (
        "                        .put(\"client.type\", \"node\")\n"
        "                        .put(settings)\n"
        "                        // InternalSettingsPreparer / env can set http.type to \"\"; ElassandraNode uses real Node + Netty module.\n"
        "                        .put(NetworkModule.HTTP_TYPE_SETTING.getKey(), \"netty4\")\n"
        "                        .build();\n"
    )
    if old_http in text:
        text = text.replace(old_http, new_http, 1)
        changed = True
    elif "NetworkModule.HTTP_TYPE_SETTING" not in text:
        print("ESSingleNodeTestCase: http.type anchor not found; skip http patch →", path, file=sys.stderr)

if "private static Class<? extends Plugin> loadNetty4PluginClass()" not in text:
    old_netty = (
        "        // nodeSettings() always sets transport.type to getTestTransportType() (mock-nio); the plugin must be on the classpath.\n"
        "        mocks.add(getTestTransportPlugin());\n"
        "        mocks.add(OpenSearchIntegTestCase.TestSeedPlugin.class);\n"
    )
    new_netty = (
        "        // nodeSettings() always sets transport.type to getTestTransportType() (mock-nio); the plugin must be on the classpath.\n"
        "        mocks.add(getTestTransportPlugin());\n"
        "        // ElassandraNode loads only explicit plugins; register Netty HTTP without a test:framework → modules Gradle edge.\n"
        "        mocks.add(loadNetty4PluginClass());\n"
        "        mocks.add(OpenSearchIntegTestCase.TestSeedPlugin.class);\n"
    )
    if old_netty in text:
        text = text.replace(old_netty, new_netty, 1)
        changed = True
    anchor = (
        "        return Collections.unmodifiableList(mocks);\n"
        "    }\n"
        "\n"
        "    public MockCassandraDiscovery getMockCassandraDiscovery() {\n"
    )
    helper = (
        "        return Collections.unmodifiableList(mocks);\n"
        "    }\n"
        "\n"
        "    @SuppressWarnings(\"unchecked\")\n"
        "    private static Class<? extends Plugin> loadNetty4PluginClass() {\n"
        "        try {\n"
        "            return (Class<? extends Plugin>) Class.forName(\"org.opensearch.transport.Netty4Plugin\");\n"
        "        } catch (ClassNotFoundException e) {\n"
        "            throw new IllegalStateException(\"org.opensearch.transport.Netty4Plugin must be on the test runtime classpath\", e);\n"
        "        }\n"
        "    }\n"
        "\n"
        "    public MockCassandraDiscovery getMockCassandraDiscovery() {\n"
    )
    if anchor in text:
        text = text.replace(anchor, helper, 1)
        changed = True

if "private static Class<? extends Plugin> loadGeoPluginClass()" not in text:
    old_geo = (
        "        // ElassandraNode loads only explicit plugins; register Netty HTTP without a test:framework → modules Gradle edge.\n"
        "        mocks.add(loadNetty4PluginClass());\n"
        "        mocks.add(OpenSearchIntegTestCase.TestSeedPlugin.class);\n"
    )
    new_geo = (
        "        // ElassandraNode loads only explicit plugins; register Netty HTTP without a test:framework → modules Gradle edge.\n"
        "        mocks.add(loadNetty4PluginClass());\n"
        "        // geo_shape lives in the OpenSearch geo module; explicit plugin loading keeps single-node tests faithful.\n"
        "        mocks.add(loadGeoPluginClass());\n"
        "        mocks.add(OpenSearchIntegTestCase.TestSeedPlugin.class);\n"
    )
    if old_geo in text:
        text = text.replace(old_geo, new_geo, 1)
        changed = True
    anchor = (
        "    private static Class<? extends Plugin> loadNetty4PluginClass() {\n"
        "        try {\n"
        "            return (Class<? extends Plugin>) Class.forName(\"org.opensearch.transport.Netty4Plugin\");\n"
        "        } catch (ClassNotFoundException e) {\n"
        "            throw new IllegalStateException(\"org.opensearch.transport.Netty4Plugin must be on the test runtime classpath\", e);\n"
        "        }\n"
        "    }\n"
        "\n"
        "    public MockCassandraDiscovery getMockCassandraDiscovery() {\n"
    )
    helper = (
        "    private static Class<? extends Plugin> loadNetty4PluginClass() {\n"
        "        try {\n"
        "            return (Class<? extends Plugin>) Class.forName(\"org.opensearch.transport.Netty4Plugin\");\n"
        "        } catch (ClassNotFoundException e) {\n"
        "            throw new IllegalStateException(\"org.opensearch.transport.Netty4Plugin must be on the test runtime classpath\", e);\n"
        "        }\n"
        "    }\n"
        "\n"
        "    @SuppressWarnings(\"unchecked\")\n"
        "    private static Class<? extends Plugin> loadGeoPluginClass() {\n"
        "        try {\n"
        "            return (Class<? extends Plugin>) Class.forName(\"org.opensearch.geo.GeoPlugin\");\n"
        "        } catch (ClassNotFoundException e) {\n"
        "            throw new IllegalStateException(\"org.opensearch.geo.GeoPlugin must be on the test runtime classpath\", e);\n"
        "        }\n"
        "    }\n"
        "\n"
        "    public MockCassandraDiscovery getMockCassandraDiscovery() {\n"
    )
    if anchor in text:
        text = text.replace(anchor, helper, 1)
        changed = True

if changed or "createNode must be true" in text or "nodeSettings() always sets transport.type" in text or "return getMockPlugins()" in text or "ElassandraNode uses real Node + Netty module" in text or "private static Class<? extends Plugin> loadNetty4PluginClass()" in text or "private static Class<? extends Plugin> loadGeoPluginClass()" in text:
    path.write_text(text, encoding="utf-8")
    print("Patched ESSingleNodeTestCase (Elassandra embedded bootstrap) →", path)
else:
    print("ESSingleNodeTestCase: no changes applied →", path)
PY
