#!/usr/bin/env python3
import os
import re
import socket
from pathlib import Path


ELASSANDRA_HOME = Path(os.environ.get("ELASSANDRA_HOME", "/usr/share/elassandra"))
CASSANDRA_CONF = Path(os.environ.get("CASSANDRA_CONF", str(ELASSANDRA_HOME / "conf")))


def env(name: str, default: str) -> str:
    value = os.environ.get(name)
    return value if value not in (None, "") else default


def default_ip() -> str:
    for name in ("CASSANDRA_LISTEN_ADDRESS", "POD_IP"):
        value = os.environ.get(name)
        if value:
            return value
    try:
        return socket.gethostbyname(socket.gethostname())
    except OSError:
        return "127.0.0.1"


def replace_required(text: str, pattern: str, replacement: str) -> str:
    new_text, count = re.subn(pattern, replacement, text, flags=re.MULTILINE)
    if count == 0:
        raise RuntimeError(f"Could not apply pattern: {pattern}")
    return new_text


listen_address = env("CASSANDRA_LISTEN_ADDRESS", default_ip())
broadcast_address = env("CASSANDRA_BROADCAST_ADDRESS", listen_address)
rpc_address = env("CASSANDRA_RPC_ADDRESS", "0.0.0.0")
broadcast_rpc_address = env("CASSANDRA_BROADCAST_RPC_ADDRESS", broadcast_address)
cluster_name = env("CASSANDRA_CLUSTER_NAME", "elassandra")
num_tokens = env("CASSANDRA_NUM_TOKENS", "16")
endpoint_snitch = env("CASSANDRA_ENDPOINT_SNITCH", "GossipingPropertyFileSnitch")
storage_port = env("CASSANDRA_STORAGE_PORT", "7000")
ssl_storage_port = env("CASSANDRA_SSL_STORAGE_PORT", "7001")
native_transport_port = env("CASSANDRA_NATIVE_TRANSPORT_PORT", "9042")
start_native_transport = env("CASSANDRA_START_NATIVE_TRANSPORT", "true").lower()
seeds = env("CASSANDRA_SEEDS", broadcast_address)
dc = env("CASSANDRA_DC", "dc1")
rack = env("CASSANDRA_RACK", "rack1")
local_jmx = env("LOCAL_JMX", "no").lower()
jmx_port = env("JMX_PORT", "7199")
debug = env("DEBUG", "false").lower() == "true"


directories = {
    "data": ELASSANDRA_HOME / "data" / "data",
    "commitlog": ELASSANDRA_HOME / "data" / "commitlog",
    "hints": ELASSANDRA_HOME / "data" / "hints",
    "cdc_raw": ELASSANDRA_HOME / "data" / "cdc_raw",
    "saved_caches": ELASSANDRA_HOME / "data" / "saved_caches",
    "logs": ELASSANDRA_HOME / "logs",
}

for directory in directories.values():
    directory.mkdir(parents=True, exist_ok=True)


cassandra_yaml = (CASSANDRA_CONF / "cassandra.yaml").read_text()
cassandra_yaml = replace_required(cassandra_yaml, r"^cluster_name: .*$", f"cluster_name: '{cluster_name}'")
cassandra_yaml = replace_required(cassandra_yaml, r"^num_tokens: .*$", f"num_tokens: {num_tokens}")
cassandra_yaml = replace_required(
    cassandra_yaml,
    r"(?ms)^# data_file_directories:\n#     - /var/lib/cassandra/data\n",
    f"data_file_directories:\n    - {directories['data']}\n",
)
cassandra_yaml = replace_required(
    cassandra_yaml,
    r"^# commitlog_directory: .*$",
    f"commitlog_directory: {directories['commitlog']}",
)
cassandra_yaml = replace_required(
    cassandra_yaml,
    r"^# hints_directory: .*$",
    f"hints_directory: {directories['hints']}",
)
cassandra_yaml = replace_required(
    cassandra_yaml,
    r"^# cdc_raw_directory: .*$",
    f"cdc_raw_directory: {directories['cdc_raw']}",
)
cassandra_yaml = replace_required(
    cassandra_yaml,
    r"^# saved_caches_directory: .*$",
    f"saved_caches_directory: {directories['saved_caches']}",
)
cassandra_yaml = replace_required(cassandra_yaml, r'^\s*- seeds: ".*"$', f'          - seeds: "{seeds}"')
cassandra_yaml = replace_required(cassandra_yaml, r"^storage_port: .*$", f"storage_port: {storage_port}")
cassandra_yaml = replace_required(cassandra_yaml, r"^ssl_storage_port: .*$", f"ssl_storage_port: {ssl_storage_port}")
cassandra_yaml = replace_required(cassandra_yaml, r"^listen_address: .*$", f"listen_address: {listen_address}")
cassandra_yaml = replace_required(cassandra_yaml, r"^# broadcast_address: .*$", f"broadcast_address: {broadcast_address}")
cassandra_yaml = replace_required(
    cassandra_yaml,
    r"^start_native_transport: .*$",
    f"start_native_transport: {'true' if start_native_transport == 'true' else 'false'}",
)
cassandra_yaml = replace_required(
    cassandra_yaml,
    r"^native_transport_port: .*$",
    f"native_transport_port: {native_transport_port}",
)
cassandra_yaml = replace_required(cassandra_yaml, r"^rpc_address: .*$", f"rpc_address: {rpc_address}")
cassandra_yaml = replace_required(
    cassandra_yaml,
    r"^# broadcast_rpc_address: .*$",
    f"broadcast_rpc_address: {broadcast_rpc_address}",
)
cassandra_yaml = replace_required(cassandra_yaml, r"^endpoint_snitch: .*$", f"endpoint_snitch: {endpoint_snitch}")
(CASSANDRA_CONF / "cassandra.yaml").write_text(cassandra_yaml)


rackdc = (CASSANDRA_CONF / "cassandra-rackdc.properties").read_text()
rackdc = replace_required(rackdc, r"^dc=.*$", f"dc={dc}")
rackdc = replace_required(rackdc, r"^rack=.*$", f"rack={rack}")
(CASSANDRA_CONF / "cassandra-rackdc.properties").write_text(rackdc)


cassandra_env = (CASSANDRA_CONF / "cassandra-env.sh").read_text()
cassandra_env = replace_required(cassandra_env, r'^JMX_PORT="7199"$', f'JMX_PORT="${{JMX_PORT:-{jmx_port}}}"')
cassandra_env = replace_required(
    cassandra_env,
    r'^JVM_OPTS="\$JVM_OPTS -javaagent:\$CASSANDRA_HOME/lib/jamm-0\.3\.2\.jar"$',
    'JAMM_JAR=$(ls "$CASSANDRA_HOME"/lib/jamm-*.jar 2>/dev/null | head -n 1)\n'
    'if [ -n "$JAMM_JAR" ] ; then\n'
    '    JVM_OPTS="$JVM_OPTS -javaagent:$JAMM_JAR"\n'
    'fi',
)
(CASSANDRA_CONF / "cassandra-env.sh").write_text(cassandra_env)


logback = (CASSANDRA_CONF / "logback.xml").read_text()
log_level = "DEBUG" if debug else "INFO"
logback = replace_required(logback, r'<root level="[^"]+">', f'<root level="{log_level}">')
logback = replace_required(
    logback,
    r'<logger name="org\.apache\.cassandra" level="[^"]+"/>',
    f'<logger name="org.apache.cassandra" level="{log_level}"/>',
)
(CASSANDRA_CONF / "logback.xml").write_text(logback)


opensearch_yml = (CASSANDRA_CONF / "opensearch.yml").read_text()
opensearch_yml = replace_required(opensearch_yml, r'^cluster\.name: .*$',
                                  f'cluster.name: "{cluster_name}"')
opensearch_yml = replace_required(opensearch_yml, r'^network\.host: .*$',
                                  "network.host: 0.0.0.0")
(CASSANDRA_CONF / "opensearch.yml").write_text(opensearch_yml)


os.environ["LOCAL_JMX"] = local_jmx
