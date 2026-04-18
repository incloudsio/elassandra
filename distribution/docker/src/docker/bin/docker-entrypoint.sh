#!/usr/bin/env bash
set -euo pipefail

umask 0002

ELASSANDRA_HOME="${ELASSANDRA_HOME:-/usr/share/elassandra}"
export ELASSANDRA_HOME
export CASSANDRA_HOME="${CASSANDRA_HOME:-$ELASSANDRA_HOME}"
export CASSANDRA_CONF="${CASSANDRA_CONF:-$ELASSANDRA_HOME/conf}"
export PATH="$ELASSANDRA_HOME/bin:$PATH"

run_as_other_user_if_needed() {
  if [[ "$(id -u)" == "0" ]]; then
    exec chroot --userspec=1000:0 / "$@"
  else
    exec "$@"
  fi
}

append_jvm_opt_if_missing() {
  local opt="$1"
  if [[ " ${JVM_OPTS:-} " != *" $opt "* ]]; then
    export JVM_OPTS="${JVM_OPTS:-} $opt"
  fi
}

if [[ $# -eq 0 ]]; then
  set -- elassandra
fi

if [[ "$1" != "elassandra" ]]; then
  exec "$@"
fi

export LOCAL_JMX="${LOCAL_JMX:-no}"
export JMX_PORT="${JMX_PORT:-7199}"
export MAX_HEAP_SIZE="${MAX_HEAP_SIZE:-1G}"
export HEAP_NEWSIZE="${HEAP_NEWSIZE:-256M}"

if [[ -z "${CASSANDRA_SEEDS:-}" && -z "${OPENSEARCH_DISCOVERY_TYPE:-}" ]]; then
  export OPENSEARCH_DISCOVERY_TYPE="single-node"
fi

append_jvm_opt_if_missing "-Dcassandra.custom_query_handler_class=org.elassandra.index.ElasticQueryHandler"

python3 /usr/local/bin/configure-elassandra.py

if [[ "$(id -u)" == "0" && -n "${TAKE_FILE_OWNERSHIP:-}" ]]; then
  chown -R 1000:0 "$ELASSANDRA_HOME/data" "$ELASSANDRA_HOME/logs"
fi

run_as_other_user_if_needed "$ELASSANDRA_HOME/bin/cassandra" -R -f
