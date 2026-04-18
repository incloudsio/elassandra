Configuration
=============

Directory Layout
----------------

Elassandra packages Cassandra and the embedded OpenSearch runtime in one installation.
The top-level layout is:

* ``conf``: node configuration and logging
* ``bin``: startup scripts, administrative commands, and plugin tools
* ``lib``: packaged JVM dependencies
* ``modules``: packaged OpenSearch modules
* ``plugins``: installed OpenSearch plugins
* ``tools``: Cassandra tooling such as ``cassandra-stress`` and ``sstabledump``
* ``data``: keyspaces, commitlogs, hints, caches, and search data files
* ``logs``: node logs

Configuration files
-------------------

The primary operational configuration remains Cassandra-centric:

* cluster name, addresses, snitch, tokens, and replication are defined through Cassandra settings
* Elassandra derives the embedded OpenSearch node identity and network bindings from those settings
* index metadata is stored in Cassandra system keyspaces managed by Elassandra

In practice, operators should treat ``cassandra.yaml`` and the rack or dc configuration
as the source of truth for node identity and topology.

Logging configuration
---------------------

Elassandra logs Cassandra and embedded OpenSearch activity through Logback.
The main operational log is ``logs/system.log``.

For deeper indexing diagnostics, raise the log level for the Elassandra indexing classes,
for example under ``org.elassandra.index``.

Multi datacenter configuration
------------------------------

Each Elassandra datacenter participates in Cassandra replication first. Search visibility
then follows the replicated keyspaces and the Elassandra metadata stored in Cassandra.

Important operational rules:

* the indexed keyspace must be replicated into the datacenter before search can open there
* metadata updates require quorum on the Elassandra metadata keyspace
* nodes in the same datacenter should run the same runtime mode and plugin set

When only a subset of datacenters should expose particular indices, use Elassandra's
datacenter tagging settings so search metadata is only activated where intended.

Elassandra Settings
-------------------

Elassandra settings can be supplied at several levels:

* JVM system properties, often with the ``es.`` prefix
* cluster defaults
* index settings
* mapping metadata

Common settings used in current deployments include:

.. list-table::
   :widths: 30 30 40
   :header-rows: 1

   * - Setting
     - Scope
     - Purpose
   * - ``keyspace``
     - index
     - Select the backing Cassandra keyspace for an index.
   * - ``replication``
     - index
     - Define the Cassandra replication map for new keyspaces.
   * - ``datacenter_tag``
     - index
     - Restrict visibility of an index to tagged datacenters.
   * - ``table_options``
     - index
     - Apply Cassandra table options during schema creation.
   * - ``search_strategy_class``
     - index or cluster
     - Control how search work is distributed across replicas.
   * - ``synchronous_refresh``
     - index, mapping, or system
     - Refresh search data immediately after writes when needed.
   * - ``drop_on_delete_index``
     - index, cluster, or system
     - Drop backing tables when deleting an index.
   * - ``index_insert_only``
     - index, mapping, or system
     - Skip read-before-write for immutable-style documents.
   * - ``token_ranges_bitset_cache``
     - index or cluster
     - Cache token-range filters for repeated searches.

Sizing and tuning
-----------------

Elassandra nodes need more CPU and memory than Cassandra-only nodes because they handle
both storage and search work.

Write performance
.................

To improve write throughput:

* index only the fields you need
* use singleton-backed fields instead of lists when data is truly single-valued
* keep refresh settings conservative for heavy write workloads
* avoid large hot partitions and very wide rows

Search performance
..................

To improve search throughput:

* keep shard data balanced by maintaining a healthy Cassandra ring
* choose an appropriate Cassandra replication factor for your search fan-out profile
* enable token-range filter caching where repeated search patterns justify it
* use Cassandra row caching carefully when queries repeatedly fetch the same rows

For cluster-level operational guidance, also see :doc:`operations` and :doc:`limitations`.
