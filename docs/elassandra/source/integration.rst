Integration
===========

Integration with an existing Cassandra cluster
----------------------------------------------

Elassandra ships a Cassandra fork maintained at
`incloudsio/cassandra <https://github.com/incloudsio/cassandra>`_ and expects
cluster nodes to run the same Elassandra build. You can start a node either with
the embedded OpenSearch runtime enabled or in Cassandra-only mode, but every node in
the same datacenter should use the same runtime mode.

Rolling replace from Cassandra to Elassandra
............................................

Before enabling search in an existing cluster, replace the Cassandra binaries on each node:

* Install the target Elassandra build.
* Reuse your cluster configuration files such as ``cassandra.yaml`` and snitch settings.
* Point Elassandra at the existing Cassandra data directories.
* Stop the standalone Cassandra process.
* Restart the node with the Elassandra runtime using ``bin/cassandra -f``.

After the full rolling replace, create mappings for existing tables or create new
OpenSearch indices as needed.

Create a new Elassandra datacenter
..................................

The procedure matches Cassandra's standard datacenter expansion flow:

* Install Elassandra on the new nodes.
* Set ``auto_bootstrap: false`` in ``conf/cassandra.yaml`` for the initial bring-up.
* Start the new nodes and verify ring membership with ``nodetool status``.
* Restart the nodes with the Elassandra runtime enabled.
* Increase replication for the indexed keyspaces into the new datacenter.
* Pull data with::

     nodetool rebuild <source-datacenter-name>

Once the data is present, Elassandra will build the local search view from the
replicated Cassandra tables. Restore ``auto_bootstrap: true`` afterwards.

.. TIP::

   If you need to replay the procedure for a node, remove it from the ring first,
   then clear its data, commitlog, and saved cache directories before starting again.

Installing OpenSearch plugins
-----------------------------

The packaged distribution includes the OpenSearch plugin CLI::

   bin/opensearch-plugin install <plugin-url-or-file>

Install the same plugin set on every node in the datacenter before restarting.

Running OpenSearch Dashboards with Elassandra
---------------------------------------------

OpenSearch Dashboards can be used as the visualization layer for Elassandra.
For local development, the repository compose file already starts a compatible
Dashboards instance. For Kubernetes deployments, enable Dashboards from the maintained
Helm chart in `incloudsio/helm-charts <https://github.com/incloudsio/helm-charts>`_.

Running Spark with Elassandra
-----------------------------

Spark integrations should target the current OpenSearch-compatible APIs exposed by
Elassandra. In practice, teams usually choose one of two approaches:

* read and write data through Cassandra connectors, then query indexed data through Elassandra
* use OpenSearch-compatible REST clients for search-specific workloads alongside Cassandra access

Validate connector compatibility against the OpenSearch 1.3 API surface used by this
repository before deploying to production.
