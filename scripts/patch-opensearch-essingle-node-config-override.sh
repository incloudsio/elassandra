#!/usr/bin/env bash
# Embedded tests: build Config in code (commitlog sync + Netty on classpath) instead of cassandra.yaml.
# Disable with -Delassandra.test.config.override=false to use YamlConfigurationLoader.
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
F="$DEST/test/framework/src/main/java/org/opensearch/test/OpenSearchSingleNodeTestCase.java"
[[ -f "$F" ]] || exit 0

if grep -q 'elassandra.test.config.override' "$F" 2>/dev/null; then
  echo "OpenSearchSingleNodeTestCase already has embedded Config supplier → $F"
  exit 0
fi

python3 - "$F" <<'PY'
import pathlib, re, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
pattern = re.compile(
    r"""        if \(ElassandraDaemon\.instance == null\) \{
.*?
            DatabaseDescriptor\.createAllDirectories\(\);
(?=\s+CountDownLatch startLatch = new CountDownLatch\(1\);)""",
    re.S,
)
if not pattern.search(text):
    print("Could not find initElassandraDeamon guard", file=sys.stderr)
    sys.exit(1)
insert = """        if (ElassandraDaemon.instance == null) {
            System.out.println("working.dir="+System.getProperty("user.dir"));
            System.out.println("cassandra.home="+System.getProperty("cassandra.home"));
            System.out.println("cassandra.config.loader="+System.getProperty("cassandra.config.loader"));
            System.out.println("cassandra.config="+System.getProperty("cassandra.config"));
            System.out.println("cassandra.config.dir="+System.getProperty("cassandra.config.dir"));
            if (System.getProperty("cassandra-rackdc.properties") == null) {
                String configDir = System.getProperty("cassandra.config.dir");
                if (configDir != null) {
                    System.setProperty("cassandra-rackdc.properties", new java.io.File(configDir, "cassandra-rackdc.properties").toURI().toString());
                }
            }
            System.out.println("cassandra-rackdc.properties="+System.getProperty("cassandra-rackdc.properties"));
            System.out.println("cassandra.storagedir="+System.getProperty("cassandra.storagedir"));
            System.out.println("logback.configurationFile="+System.getProperty("logback.configurationFile"));

            if (System.getProperty("cassandra.custom_query_handler_class") == null) {
                System.setProperty("cassandra.custom_query_handler_class", "org.elassandra.index.ElasticQueryHandler");
            }
            System.out.println("cassandra.custom_query_handler_class="+System.getProperty("cassandra.custom_query_handler_class"));

            if (Boolean.parseBoolean(System.getProperty("elassandra.test.config.override", "true"))) {
                DatabaseDescriptor.daemonInitialization(() -> {
                    String homeProp = System.getProperty("cassandra.home");
                    if (homeProp == null) {
                        throw new IllegalStateException("cassandra.home must be set for Elassandra embedded tests");
                    }
                    java.io.File home = new java.io.File(homeProp);
                    org.apache.cassandra.config.Config c = new org.apache.cassandra.config.Config();
                    c.commitlog_sync = org.apache.cassandra.config.Config.CommitLogSync.periodic;
                    c.commitlog_sync_period_in_ms = 10000;
                    c.data_file_directories = new String[] { new java.io.File(home, "data").getPath() };
                    c.commitlog_directory = new java.io.File(home, "commitlog").getPath();
                    c.saved_caches_directory = new java.io.File(home, "saved_caches").getPath();
                    c.hints_directory = new java.io.File(home, "hints").getPath();
                    c.storage_port = Integer.getInteger("elassandra.test.storage_port", 17100);
                    c.partitioner = "org.apache.cassandra.dht.Murmur3Partitioner";
                    c.endpoint_snitch = "org.apache.cassandra.locator.GossipingPropertyFileSnitch";
                    java.util.Map<String, String> seedParams = java.util.Collections.singletonMap("seeds", "127.0.0.1");
                    c.seed_provider = new org.apache.cassandra.config.ParameterizedClass(
                        "org.apache.cassandra.locator.SimpleSeedProvider",
                        seedParams
                    );
                    return c;
                });
            } else {
                DatabaseDescriptor.daemonInitialization();
            }
            DatabaseDescriptor.createAllDirectories();"""
text = pattern.sub(insert, text, count=1)
path.write_text(text, encoding="utf-8")
print("Patched embedded Config supplier →", path)
PY
