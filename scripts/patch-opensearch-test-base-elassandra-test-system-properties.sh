#!/usr/bin/env bash
# Restore Elassandra test defaults in the sidecar test JVMs:
# - es.synchronous_refresh=true so CQL writes are immediately searchable in tests
# - es.drop_on_delete_index=true so index deletion also drops backing keyspaces/tables
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
F="$DEST/buildSrc/src/main/java/org/opensearch/gradle/OpenSearchTestBasePlugin.java"
[[ -f "$F" ]] || exit 0

python3 - "$F" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

needle = '            test.systemProperty("tests.logger.level", "WARN");\n'
if needle not in text:
    print("patch-opensearch-test-base-elassandra-test-system-properties: anchor not found", file=sys.stderr)
    sys.exit(1)

legacy_insert = (
    '            /* Elassandra test defaults: real-time search + drop backing tables */\n'
    '            test.systemProperty("es.synchronous_refresh", "true");\n'
    '            test.systemProperty("es.drop_on_delete_index", "true");\n'
)

prior_insert = (
    '            /* Elassandra test defaults: Cassandra config + real-time search + drop backing tables */\n'
    '            if (project.getPath().equals(":server")) {\n'
    '                test.systemProperty("cassandra.home", test.getWorkingDir().getAbsolutePath());\n'
    '                test.systemProperty("cassandra.logdir", test.getWorkingDir().getAbsolutePath());\n'
    '                test.systemProperty("logback.configurationFile", project.getProjectDir() + "/src/test/resources/conf/logback.xml");\n'
    '                test.systemProperty("cassandra.config", "file://" + project.getProjectDir() + "/src/test/resources/conf/cassandra-opensearch-sidecar.yaml");\n'
    '                test.systemProperty("cassandra.config.dir", project.getProjectDir() + "/src/test/resources/conf");\n'
    '                test.systemProperty("cassandra-rackdc.properties", "file://" + project.getProjectDir() + "/src/test/resources/conf/cassandra-rackdc.properties");\n'
    '                test.systemProperty("cassandra.storagedir", test.getWorkingDir().getAbsolutePath());\n'
    '                test.systemProperty("cassandra.custom_query_handler_class", "org.elassandra.index.ElasticQueryHandler");\n'
    '            }\n'
    '            test.systemProperty("es.synchronous_refresh", "true");\n'
    '            test.systemProperty("es.drop_on_delete_index", "true");\n'
)

loader_insert = (
    '            /* Elassandra test defaults: Cassandra config + real-time search + drop backing tables */\n'
    '            if (project.getPath().equals(":server")) {\n'
    '                String cassandraHome = System.getProperty("cassandra.home", test.getWorkingDir().getAbsolutePath());\n'
    '                String cassandraConfig = System.getProperty(\n'
    '                    "cassandra.config",\n'
    '                    "file://" + project.getProjectDir() + "/src/test/resources/conf/cassandra-opensearch-sidecar.yaml"\n'
    '                );\n'
    '                String cassandraConfigDir = System.getProperty("cassandra.config.dir", project.getProjectDir() + "/src/test/resources/conf");\n'
    '                String cassandraRackDc = System.getProperty(\n'
    '                    "cassandra-rackdc.properties",\n'
    '                    "file://" + cassandraConfigDir + "/cassandra-rackdc.properties"\n'
    '                );\n'
    '                String logbackConfig = System.getProperty(\n'
    '                    "logback.configurationFile",\n'
    '                    project.getProjectDir() + "/src/test/resources/conf/logback.xml"\n'
    '                );\n'
    '                test.systemProperty("cassandra.home", cassandraHome);\n'
    '                test.systemProperty("cassandra.logdir", test.getWorkingDir().getAbsolutePath());\n'
    '                test.systemProperty("logback.configurationFile", logbackConfig);\n'
    '                test.systemProperty("cassandra.config", cassandraConfig);\n'
    '                test.systemProperty("cassandra.config.dir", cassandraConfigDir);\n'
    '                test.systemProperty("cassandra-rackdc.properties", cassandraRackDc);\n'
    '                test.systemProperty("cassandra.config.loader", "org.elassandra.config.YamlTestConfigurationLoader");\n'
    '                test.systemProperty("cassandra.storagedir", test.getWorkingDir().getAbsolutePath());\n'
    '                test.systemProperty("cassandra.custom_query_handler_class", "org.elassandra.index.ElasticQueryHandler");\n'
    '            }\n'
    '            test.systemProperty("es.synchronous_refresh", "true");\n'
    '            test.systemProperty("es.drop_on_delete_index", "true");\n'
)

new_insert = (
    '            /* Elassandra test defaults: Cassandra config + real-time search + drop backing tables */\n'
    '            if (project.getPath().equals(":server")) {\n'
    '                String cassandraHome = System.getProperty("cassandra.home", test.getWorkingDir().getAbsolutePath());\n'
    '                String cassandraConfig = System.getProperty(\n'
    '                    "cassandra.config",\n'
    '                    "file://" + project.getProjectDir() + "/src/test/resources/conf/cassandra-opensearch-sidecar.yaml"\n'
    '                );\n'
    '                String cassandraConfigDir = System.getProperty("cassandra.config.dir", project.getProjectDir() + "/src/test/resources/conf");\n'
    '                String cassandraRackDc = System.getProperty(\n'
    '                    "cassandra-rackdc.properties",\n'
    '                    "file://" + cassandraConfigDir + "/cassandra-rackdc.properties"\n'
    '                );\n'
    '                String logbackConfig = System.getProperty(\n'
    '                    "logback.configurationFile",\n'
    '                    project.getProjectDir() + "/src/test/resources/conf/logback.xml"\n'
    '                );\n'
    '                test.systemProperty("cassandra.home", cassandraHome);\n'
    '                test.systemProperty("cassandra.logdir", test.getWorkingDir().getAbsolutePath());\n'
    '                test.systemProperty("logback.configurationFile", logbackConfig);\n'
    '                test.systemProperty("cassandra.config", cassandraConfig);\n'
    '                test.systemProperty("cassandra.config.dir", cassandraConfigDir);\n'
    '                test.systemProperty("cassandra-rackdc.properties", cassandraRackDc);\n'
    '                test.systemProperty("cassandra.storagedir", test.getWorkingDir().getAbsolutePath());\n'
    '                test.systemProperty("cassandra.custom_query_handler_class", "org.elassandra.index.ElasticQueryHandler");\n'
    '            }\n'
    '            test.systemProperty("es.synchronous_refresh", "true");\n'
    '            test.systemProperty("es.drop_on_delete_index", "true");\n'
)

for block in (legacy_insert, prior_insert, loader_insert, new_insert):
    while block in text:
        text = text.replace(block, "", 1)

text = text.replace(needle, new_insert + needle, 1)

path.write_text(text, encoding="utf-8")
print("Patched OpenSearchTestBasePlugin Elassandra test defaults →", path)
PY
