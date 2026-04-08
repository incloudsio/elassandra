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

   ./scripts/opensearch-port-bootstrap.sh
   # equivalent to:
   ./scripts/clone-opensearch-upstream.sh
   # then (in the clone): git checkout -B elassandra-os-1.3 1.3.20

Then:

.. code-block:: bash

   cd ../opensearch-upstream   # or your OPENSEARCH_CLONE_DIR
   git branch --show-current   # expect elassandra-os-1.3

Use **Java 11+** and the Gradle wrapper shipped in that tree. Do not expect the Elassandra **6.8** Gradle wrapper to drive the OpenSearch build.

Sync ``org.elassandra.*`` and rewrite imports (side-car)
........................................................

From this repository (after bootstrap):

.. code-block:: bash

   ./scripts/sync-elassandra-to-opensearch-sidecar.sh
   ./scripts/rewrite-elassandra-imports-for-opensearch.sh "${OPENSEARCH_CLONE_DIR:-../opensearch-upstream}"

Build the Cassandra jar when needed (from this repo):

.. code-block:: bash

   ./scripts/build-elassandra-cassandra-jar.sh

To run a compile attempt (expect failures until the forked ``org.opensearch`` sources are replayed):

.. code-block:: bash

   JAVA_HOME=/path/to/jdk-11 ./scripts/opensearch-sidecar-compile-try.sh

If you drive OpenSearch ``gradlew`` manually, pass the jar path via ``GRADLE_OPTS`` (``-D`` on the CLI is not always forwarded) and ``-I`` the init script under ``gradle/opensearch-sidecar-elassandra.init.gradle``. After Cassandra resolves, remaining errors are usually fork-only types such as ``CqlMapper`` that must be merged from the Elasticsearch tree.

The same ``rewrite-elassandra-imports-for-opensearch.sh`` pass flattens nested metric imports (``metrics.min.*`` → ``metrics.*``), renames ``IndexMetaData`` / ``MetaData`` to ``IndexMetadata`` / ``Metadata``, rewrites ``.metaData()`` → ``.metadata()``, and adjusts ``getTotalHits()`` for Lucene ``TotalHits`` (7.x+). Types such as ``ObjectMapper`` must still implement Elassandra’s ``CqlMapper`` in the merged fork.

List ``org/elasticsearch`` sources that mention Elassandra / Strapdata (likely fork touchpoints for the rebase):

.. code-block:: bash

   ./scripts/list-elasticsearch-fork-touchpoints.sh

Target version pins for the side-car (from ``buildSrc/version.properties``):

.. code-block:: bash

   ./scripts/print-opensearch-port-pins.sh

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

Mapper fork (CqlMapper / CQL columns)
.....................................

Elassandra adds ``CqlMapper``, CQL-related state on ``ObjectMapper`` / ``FieldMapper`` / ``MappedFieldType``,
and parsing hooks in ``TypeParsers``. Stock OpenSearch does not include these; you must **merge** the
Elasticsearch 6.8 fork in ``server/src/main/java/org/elasticsearch/index/mapper/`` into the matching
``org.opensearch.index.mapper`` types (often starting with ``ObjectMapper`` and ``FieldMapper``).

Export the full forked mapper directory next to your OpenSearch clone as a **read-only reference**
for diff and 3-way merge (does not overwrite OpenSearch sources):

.. code-block:: bash

   ./scripts/export-elassandra-mapper-fork-for-opensearch-merge.sh

Output path: ``<OpenSearch clone>/elassandra-mapper-fork-reference/org/elasticsearch/index/mapper/``.

To stage the fork inside this repo with ``package org.opensearch.index.mapper`` and the same automated
rewrites used for the side-car (for diffing against upstream without touching the OpenSearch clone):

.. code-block:: bash

   ./scripts/stage-elassandra-mapper-fork-as-opensearch.sh
   ./scripts/prioritize-mapper-fork-merge.sh

Default output: ``build/elassandra-mapper-staged-opensearch/server/src/main/java/org/opensearch/index/mapper/``.

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
* After the test framework is rebased onto OpenSearch, expect renames such as
  ``ESSingleNodeTestCase`` → ``org.opensearch.test.OpenSearchSingleNodeTestCase`` and
  ``ESTestCase`` → ``OpenSearchTestCase`` (see upstream ``test/framework`` in the OpenSearch tree).
