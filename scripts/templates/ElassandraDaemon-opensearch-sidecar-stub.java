/*
 * Compile stub for OpenSearch side-car (:server:compileJava and test-framework compile).
 * Full ElassandraDaemon lives in this repo under org.apache.cassandra.service and targets Elasticsearch 6.8 bootstrap.
 *
 * This stub lets ESSingleNodeTestCase run activate() + newNode() without the full CassandraDaemon merge.
 * {@link org.opensearch.bootstrap.Bootstrap} is package-private — natives are initialized by the test framework
 * ({@code BootstrapForTesting}); we only unblock {@code ringReady()} and construct {@link org.opensearch.node.Node}.
 */
package org.apache.cassandra.service;

import org.opensearch.bootstrap.BootstrapCheck;
import org.opensearch.bootstrap.BootstrapContext;
import org.opensearch.common.settings.Settings;
import org.opensearch.common.transport.BoundTransportAddress;
import org.opensearch.env.Environment;
import org.opensearch.node.Node;
import org.opensearch.node.NodeValidationException;
import org.opensearch.plugins.ClusterPlugin;
import org.opensearch.plugins.Plugin;

import java.util.ArrayList;
import java.util.Collection;
import java.util.List;

/**
 * Minimal API surface used by {@code org.opensearch.test.ESSingleNodeTestCase} after import rewrites.
 * {@code instance} must start as {@code null} so static init in the test base runs {@code activate()} and {@code ringReady()}.
 */
public class ElassandraDaemon {

    /** Must be null at class init — see ESSingleNodeTestCase#initElassandraDeamon */
    public static ElassandraDaemon instance = null;

    protected Environment env;
    private Node node;

    public ElassandraDaemon(Environment env) {
        instance = this;
        this.env = env;
    }

    public Node node() {
        return node;
    }

    public Node node(Node newNode) {
        this.node = newNode;
        return newNode;
    }

    public Settings nodeSettings(Settings settings) {
        return settings;
    }

    /**
     * Stores the environment and invokes {@link #ringReady()} (overridden by ESSingleNodeTestCase to unblock init).
     */
    public void activate(
        boolean tool,
        boolean daemonize,
        Settings settings,
        Environment environment,
        Collection<Class<? extends Plugin>> classpathPlugins
    ) {
        this.env = environment;
        ringReady();
    }

    public Node newNode(
        Settings settings,
        Collection<Class<? extends Plugin>> classpathPlugins,
        boolean forbidPrivateIndexSettings
    ) {
        Settings merged = nodeSettings(settings);
        List<Class<? extends Plugin>> plugins = new ArrayList<>(classpathPlugins);
        plugins.add(ElassandraPlugin.class);
        Environment nodeEnv = new Environment(merged, env.configFile());
        this.node = new Node(nodeEnv, plugins, forbidPrivateIndexSettings) {
            @Override
            protected void validateNodeBeforeAcceptingRequests(
                final BootstrapContext context,
                final BoundTransportAddress boundTransportAddress,
                List<BootstrapCheck> checks
            ) throws NodeValidationException {
                // org.opensearch.bootstrap.BootstrapChecks is package-private; base Node default is no-op
            }
        };
        return this.node;
    }

    public void ringReady() {}

    public static class ElassandraPlugin extends Plugin implements ClusterPlugin {
        public ElassandraPlugin() {
            super();
        }

        @Override
        public void onNodeStarted() {
            if (instance != null) {
                instance.onNodeStarted();
            }
        }
    }

    protected void onNodeStarted() {
        // Real daemon notifies setup listeners; stub is no-op
    }
}
