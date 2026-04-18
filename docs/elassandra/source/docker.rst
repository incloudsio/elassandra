
Docker image
============

The repository now carries the Elassandra image build sources directly under ``distribution/docker``.
The Docker build reuses the assembled Linux distribution from this repository and overlays the Cassandra
startup scripts and configuration needed to start ``org.apache.cassandra.service.ElassandraDaemon``.

Build the image locally
.......................

From the repository root::

  ./gradlew :distribution:docker:buildDockerImage

The local tag produced by the Gradle task is::

  elassandra:test

Start a single node
...................

Run a local Elassandra container::

  docker run --name node0 \
    -p 9042:9042 \
    -p 9200:9200 \
    -e MAX_HEAP_SIZE=1200m \
    -e HEAP_NEWSIZE=300m \
    -e JVM_OPTS=-Dcassandra.custom_query_handler_class=org.elassandra.index.ElasticQueryHandler \
    elassandra:test

Then inspect the node::

  docker exec -it node0 nodetool status
  docker exec -it node0 cqlsh
  docker exec -it node0 curl localhost:9200

Supported environment variables
...............................

The image configures ``conf/cassandra.yaml`` and ``conf/cassandra-rackdc.properties`` from environment
variables at container start. The first-pass runtime contract is intentionally small and matches the
Helm chart values:

+-------------------------------+-------------------------------------------------------------+
| Variable                      | Description                                                 |
+===============================+=============================================================+
| ``CASSANDRA_LISTEN_ADDRESS``  | Cassandra listen address. Defaults to the container IP.     |
+-------------------------------+-------------------------------------------------------------+
| ``CASSANDRA_BROADCAST_ADDRESS`` | Gossip and broadcast address. Defaults to listen address. |
+-------------------------------+-------------------------------------------------------------+
| ``CASSANDRA_RPC_ADDRESS``     | CQL bind address. Defaults to ``0.0.0.0``.                  |
+-------------------------------+-------------------------------------------------------------+
| ``CASSANDRA_BROADCAST_RPC_ADDRESS`` | CQL address advertised to clients.                    |
+-------------------------------+-------------------------------------------------------------+
| ``CASSANDRA_SEEDS``           | Comma-separated seed hosts for gossip bootstrap.            |
+-------------------------------+-------------------------------------------------------------+
| ``CASSANDRA_CLUSTER_NAME``    | Cluster name written to ``cassandra.yaml``.                 |
+-------------------------------+-------------------------------------------------------------+
| ``CASSANDRA_NUM_TOKENS``      | Number of virtual nodes assigned to the container.          |
+-------------------------------+-------------------------------------------------------------+
| ``CASSANDRA_DC``              | Datacenter for ``cassandra-rackdc.properties``.             |
+-------------------------------+-------------------------------------------------------------+
| ``CASSANDRA_RACK``            | Rack for ``cassandra-rackdc.properties``.                   |
+-------------------------------+-------------------------------------------------------------+
| ``CASSANDRA_ENDPOINT_SNITCH`` | Snitch implementation, default ``GossipingPropertyFileSnitch``. |
+-------------------------------+-------------------------------------------------------------+
| ``MAX_HEAP_SIZE``             | JVM heap upper bound for Cassandra/Elassandra.              |
+-------------------------------+-------------------------------------------------------------+
| ``HEAP_NEWSIZE``              | Young-generation heap size.                                 |
+-------------------------------+-------------------------------------------------------------+
| ``JVM_OPTS``                  | Additional JVM options. The image adds the Elassandra query |
|                               | handler if it is not already present.                       |
+-------------------------------+-------------------------------------------------------------+
| ``DEBUG``                     | Switch the packaged ``logback.xml`` root logger to DEBUG.   |
+-------------------------------+-------------------------------------------------------------+

Filesystem layout
.................

The image uses an installation rooted at ``/usr/share/elassandra``:

- ``/usr/share/elassandra/bin``: Cassandra and Elassandra startup scripts
- ``/usr/share/elassandra/conf``: Cassandra and OpenSearch configuration
- ``/usr/share/elassandra/data``: data, commitlog, hints, CDC, and saved caches
- ``/usr/share/elassandra/logs``: log files

Exposed ports
.............

- ``7000``: intra-node communication
- ``7001``: TLS intra-node communication
- ``7199``: JMX
- ``9042``: CQL
- ``9160``: thrift
- ``9200``: OpenSearch HTTP
- ``9300``: OpenSearch transport

Local cluster example
.....................

For a small local multi-node test environment, use ``ci/docker-compose.yml`` after building the image::

  docker-compose -f ci/docker-compose.yml up -d --scale node=0
  docker-compose -f ci/docker-compose.yml up -d --scale node=1

For long-lived containerized deployments, prefer the maintained Helm chart in
``https://github.com/incloudsio/helm-charts/tree/master/charts/elassandra``.

