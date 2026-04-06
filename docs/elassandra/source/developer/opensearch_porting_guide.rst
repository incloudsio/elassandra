.. _opensearch_porting_guide:

OpenSearch 1.3.x porting guide (codebase map)
=============================================

This repository currently ships a **fork of Elasticsearch 6.8.4** integrated with Cassandra.
The modernization target is **OpenSearch 1.3.x** (Elasticsearch 7.10 lineage): new Gradle layout,
``org.opensearch.*`` packages, and different node/bootstrap APIs.

Recommended approach
--------------------

#. Create a branch from the upstream tag **OpenSearch 1.3.20** (or latest 1.3.x), e.g. ``elassandra-os-1.3``.
#. Port **Elassandra** behavior in the order below (each step should compile before moving on).
#. Keep Elassandra-specific code in ``org.elassandra.*``; migrate call sites to OpenSearch APIs.

Clone upstream (side-by-side)
.............................

From the Elassandra repo root you can clone a pinned OpenSearch tree next to this project (adjust paths as you like):

.. code-block:: bash

   ./scripts/clone-opensearch-upstream.sh
   # or explicitly:
   OPENSEARCH_TAG=1.3.20 OPENSEARCH_CLONE_DIR=../opensearch-1.3.20 \
     ./scripts/clone-opensearch-upstream.sh

Then:

.. code-block:: bash

   cd ../opensearch-1.3.20   # or your OPENSEARCH_CLONE_DIR
   git checkout -b elassandra-os-1.3

Use **Java 11+** and the Gradle wrapper shipped in that tree. Do not expect the Elassandra **6.8** Gradle wrapper to drive the OpenSearch build.

Bootstrap and process model
---------------------------

* **Current:** ``org.apache.cassandra.service.ElassandraDaemon`` extends ``CassandraDaemon``, calls
  ``org.elasticsearch.bootstrap.Bootstrap`` and ``org.elasticsearch.node.Node``.
* **Target:** Same class location in the **Cassandra** fork; update imports to
  ``org.opensearch.bootstrap.Bootstrap`` and ``org.opensearch.node.Node``, and reconcile
  ``Node`` construction / validation hooks with OpenSearch 1.3.

Cluster state, gateway, discovery
---------------------------------

* ``org.elassandra.discovery.CassandraDiscovery`` — map to OpenSearch discovery plugin SPI.
* ``org.elassandra.gateway.CassandraGatewayService`` / ``CassandraGatewayModule`` — align with
  OpenSearch gateway and persisted cluster state services.
* Patched upstream types (examples): ``org.elasticsearch.cluster.service.ClusterService``,
  ``MasterService``, ``DiscoveryModule``, ``GatewayModule`` → move patches to
  ``org.opensearch.cluster.*`` equivalents.

Routing and search
------------------

* ``org.elasticsearch.cluster.routing.OperationRouting`` — token-aware routing.
* ``org.elassandra.index.search.TokenRangesService``, ``TokenRangesSearcherWrapper``, related
  bitset/cache types — rebase onto OpenSearch search execution paths.
* ``org.elasticsearch.search.SearchService``, ``FetchPhase``, ``CqlFetchPhase``.

Metadata and mapping
--------------------

* ``MetaDataCreateIndexService``, ``IndexMetaData``, ``IndicesModule``, ``IndexModule``,
  ``MapperService``, ``DocumentMapper`` — heavy ES 6.8 touch points; expect largest diff vs 1.3.

Shard coordination
------------------

* ``org.elassandra.shard.CassandraShardStateListener``, ``CassandraShardStartedBarrier``.

Secondary index bridge
----------------------

* ``org.elassandra.index.ElasticSecondaryIndex`` and related index/query handlers — JVM bridge
  from Cassandra writes to the search engine; must compile against OpenSearch client/index APIs.

Modules and tests
-----------------

* ``modules/ingest-common`` Elassandra processors (e.g. timeuuid, base64).
* ``server/src/test/java/org/elassandra`` — update test framework imports; keep
  “single node per JVM” assumptions documented in ``MockCassandraDiscovery``.
