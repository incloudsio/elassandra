Installation
============

The canonical project site is `Elassandra.org <https://elassandra.org/>`_.

The maintained repository line documented here targets **Apache Cassandra 4.0.x** with an
embedded **OpenSearch 1.3.x** runtime. Use **Java 11** for both the Gradle build and the
packaged server runtime.

Elassandra can be installed as:

- tarball_
- `deb`_
- `rpm`_
- Docker image (see :doc:`docker`)
- Helm chart (see :doc:`helm`)

.. important::

   Elassandra runs both Cassandra storage and OpenSearch indexing in the same JVM.
   Size hosts accordingly. For local development, allocate at least 4 GB of RAM.
   For production, follow the sizing guidance in :doc:`configuration`.

Tarball
-------

Check your Java runtime first::

    java -version

The current line should report Java 11 or newer.

Download the release tarball:

.. parsed-literal::

    wget |tgz_url|

Extract it and enter the installation directory:

.. parsed-literal::

    tar -xzf elassandra-|release|.tar.gz
    cd elassandra-|release|

Start Elassandra in the foreground::

    bin/cassandra -f

Verify that both Cassandra and OpenSearch are up::

    bin/nodetool status
    bin/cqlsh -e "DESCRIBE KEYSPACES"
    curl -s http://localhost:9200/

The HTTP response should advertise the current Elassandra release and the embedded
OpenSearch version. For example:

.. parsed-literal::

    {
      "name" : "127.0.0.1",
      "cluster_name" : "Test Cluster",
      "cluster_uuid" : "...",
      "version" : {
        "number" : "|version|"
      },
      "tagline" : "The OpenSearch Project: https://opensearch.org/"
    }

For production installs, disable swap and use a supported allocator such as
`jemalloc <https://jemalloc.net/>`_ where appropriate for your platform.

Deb
---

.. include:: adhoc_deb.rst

Rpm
---

.. include:: adhoc_rpm.rst

Docker image
------------

See :doc:`docker` for container image build, environment variables, and the local
compose-based cluster example.

Helm chart
----------

See :doc:`helm` for the maintained Kubernetes chart, provider presets, and example
installation commands.

Running Cassandra only
----------------------

If a datacenter should run Cassandra storage without the embedded search runtime,
set ``CASSANDRA_DAEMON`` to ``org.apache.cassandra.service.CassandraDaemon`` in the
service environment for those nodes. All nodes in a datacenter should use the same
runtime mode.
