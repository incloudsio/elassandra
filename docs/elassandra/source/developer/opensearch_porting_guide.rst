.. _opensearch_porting_guide:

OpenSearch 1.3.x porting guide (codebase map)
=============================================

This repository now ships an **OpenSearch 1.3.x**-based Elassandra integration on top of Cassandra 4.0.
Use this guide when rebasing to a newer OpenSearch tag or when replaying the Elassandra-specific delta
onto a fresh upstream checkout in the side-car harness.

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

Use **Java 11+** and the Gradle wrapper shipped in that tree. Do not expect tooling from the legacy 6.8 line to drive the OpenSearch build.

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

``opensearch-sidecar-compile-try.sh`` calls ``scripts/opensearch-sidecar-prepare.sh``, which syncs ``org.elassandra.*``, applies patch scripts, and rewrites imports—**without** running Gradle. To re-run only the prepare step (e.g. after editing a patch script):

.. code-block:: bash

   ./scripts/opensearch-sidecar-prepare.sh "${OPENSEARCH_CLONE_DIR:-../incloudsio-opensearch}"

After main and test sources compile, you can probe **integration tests** in the side-car (usually **not** green until ``ElassandraDaemon`` and full runtime wiring land):

.. code-block:: bash

   JAVA_HOME=/path/to/jdk-11 ./scripts/opensearch-sidecar-test-try.sh
   # Optional: OPENSEARCH_SIDECAR_TEST_PATTERN='org.elassandra.*' …

See ``server/OPENSEARCH_PORT.md`` in this repo for Cassandra jar setup, ``GRADLE_OPTS``, ``RUNTIME_JAVA_HOME`` (avoids OpenSearch downloading a separate test JDK), optional CI workflows, and expectations for ``:server:test``. If you hit Lucene mock-filesystem / ``java.io.tmpdir`` / Gradle worker exit **100**, try ``OPENSEARCH_SIDECAR_TESTS_JVMS=1`` (single forked test JVM) and read the header of ``gradle/opensearch-sidecar-elassandra.init.gradle``.

If you drive OpenSearch ``gradlew`` manually, pass the jar path via ``GRADLE_OPTS`` (``-D`` on the CLI is not always forwarded) and ``-I`` the init script under ``gradle/opensearch-sidecar-elassandra.init.gradle``. After Cassandra resolves, remaining errors are usually fork-only types such as ``CqlMapper`` that must be merged from the legacy mapper fork.

The same ``rewrite-elassandra-imports-for-opensearch.sh`` pass flattens nested metric imports (``metrics.min.*`` → ``metrics.*``), renames ``IndexMetaData`` / ``MetaData`` to ``IndexMetadata`` / ``Metadata``, rewrites ``.metaData()`` → ``.metadata()``, and adjusts ``getTotalHits()`` for Lucene ``TotalHits`` (7.x+). Types such as ``ObjectMapper`` must still implement Elassandra’s ``CqlMapper`` in the merged fork.

List the legacy fork touchpoints with the repository helper script and refresh the checked-in
touchpoint snapshot after large fork edits.

Target version pins for the side-car (from ``buildSrc/version.properties``):

.. code-block:: bash

   ./scripts/print-opensearch-port-pins.sh

Bootstrap and process model
---------------------------

* **Merged baseline:** ``org.apache.cassandra.service.ElassandraDaemon`` in the Cassandra fork extends
  ``CassandraDaemon`` and calls ``org.opensearch.bootstrap.Bootstrap`` / ``org.opensearch.node.Node``.
* **Future rebases:** Keep the same class location in the **Cassandra** fork and reconcile
  ``Node`` construction / validation hooks with the target OpenSearch version.

Cluster state, gateway, discovery
---------------------------------

* ``org.elassandra.discovery.CassandraDiscovery`` — map to OpenSearch discovery plugin SPI.
* ``org.elassandra.gateway.CassandraGatewayService`` / ``CassandraGatewayModule`` — align with
  OpenSearch gateway and persisted cluster state services.
* Patched upstream types (examples): ``org.opensearch.cluster.service.ClusterService``,
  ``MasterService``, ``DiscoveryModule``, ``GatewayModule`` → move patches to
  ``org.opensearch.cluster.*`` equivalents.

Routing and search
------------------

* ``org.opensearch.cluster.routing.OperationRouting`` — token-aware routing.
* ``org.elassandra.index.search.TokenRangesService``, ``TokenRangesSearcherWrapper``, related
  bitset/cache types — rebase onto OpenSearch search execution paths.
* ``org.opensearch.search.SearchService``, ``FetchPhase``, ``CqlFetchPhase``.

Metadata and mapping
--------------------

* ``MetaDataCreateIndexService``, ``IndexMetaData``, ``IndicesModule``, ``IndexModule``,
  ``MapperService``, ``DocumentMapper`` — heavy legacy touch points; expect the largest diff vs 1.3.

Mapper fork (CqlMapper / CQL columns)
.....................................

Elassandra adds ``CqlMapper``, CQL-related state on ``ObjectMapper`` / ``FieldMapper`` / ``MappedFieldType``,
and parsing hooks in ``TypeParsers``. Stock OpenSearch does not include these; you must **merge** the
legacy mapper fork into the matching ``org.opensearch.index.mapper`` types (often starting with
``ObjectMapper`` and ``FieldMapper``).

Export the full forked mapper directory next to your OpenSearch clone as a **read-only reference**
for diff and 3-way merge (does not overwrite OpenSearch sources):

.. code-block:: bash

   ./scripts/export-elassandra-mapper-fork-for-opensearch-merge.sh

Output path: ``<OpenSearch clone>/elassandra-mapper-fork-reference/``.

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
