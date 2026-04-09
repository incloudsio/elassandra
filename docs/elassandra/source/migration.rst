.. _migration_modern_stack:

Migrating to Cassandra 4.0.x and OpenSearch 1.3.x
===================================================

This document describes **operator-facing** changes when moving from legacy Elassandra
(Elasticsearch 6.8.x + Cassandra 3.11.x) to the modern stack maintained at
`https://elassandra.org/ <https://elassandra.org/>`_ (Cassandra **4.0.x** + OpenSearch **1.3.x**).

There is **no supported in-place upgrade** of the embedded Lucene indices from ES 6.8 to
OpenSearch 1.3. Plan one of:

* **Rebuild search from Cassandra** — use Elassandra’s Cassandra-backed tables as source of truth
  and recreate indices/mappings on the new cluster (typical for deployments that always index from C*).
* **Reindex via snapshot/restore** — only if you have a compatible snapshot workflow; ES 6.8 indices
  are not directly compatible with OpenSearch 1.3 Lucene codecs. Expect a **full reindex** using an
  external tool or dual-write period.

HTTP API and clients
--------------------

* OpenSearch 1.3 follows the **Elasticsearch 7.10** REST conventions in most places, **not** 6.8.
* Remove document **types** from URLs and mappings (single ``_doc`` type model from ES 7+).
* Use **OpenSearch** REST clients or Elasticsearch 7.10-compatible clients pointing at OpenSearch 1.3,
  not Elasticsearch 6.x transport or REST clients.

Dashboards
----------

* **Kibana 6.x** is not compatible with OpenSearch. Use **OpenSearch Dashboards** 1.x aligned with
  your server minor version.

Java runtime
------------

* Target runtime is **Java 11** (or newer LTS supported by your chosen Cassandra 4.0 and OpenSearch
  1.3 patch releases).

Cassandra
---------

* All nodes in an Elassandra cluster must run the **same Elassandra build** (Cassandra 4.0–based).
* Review **secondary index** and **schema extension** behavior after upgrade; validate rebuild and repair
  procedures in a staging cluster.

Implementation status (repository)
------------------------------------

.. list-table::
   :widths: 30 70
   :header-rows: 1

   * - Component
     - Pin / branch (check ``buildSrc/version.properties`` and submodules)
   * - Elassandra application repo
     - `incloudsio/elassandra <https://github.com/incloudsio/elassandra>`_ (integration branches may track modernization work).
   * - Cassandra fork
     - `incloudsio/cassandra <https://github.com/incloudsio/cassandra>`_ — **3.11** line ``cassandra-3.11.9-elassandra`` (default submodule); **4.0** line ``cassandra-4.0.x-elassandra`` (Maven ``groupId`` ``io.inclouds.cassandra``). Switch with ``scripts/use-cassandra-40-submodule.sh`` when porting the JVM.
   * - OpenSearch port
     - Bootstrap side-car tree with ``scripts/opensearch-port-bootstrap.sh`` (branch ``elassandra-os-1.3`` from tag **1.3.20**); port ``org.elassandra.*`` per :ref:`opensearch_porting_guide`.
   * - Legacy version verify
     - Root Gradle ``verifyVersions`` can be skipped with ``-Pelassandra.skipLegacyVersionVerify`` while the stack moves off Strapdata snapshot metadata.

Target pins (when the modern stack ships)
------------------------------------------

These values are recorded in ``buildSrc/version.properties`` as ``opensearch_port`` and ``lucene_opensearch`` (they match upstream OpenSearch **1.3.20**). The Cassandra **4.0** artifact version tracks ``server/cassandra/build.xml`` ``base.version`` after ``scripts/use-cassandra-40-submodule.sh`` (typically **4.0.20** on branch ``cassandra-4.0.x-elassandra``).

Operator validation (staging)
------------------------------

* Exercise **rebuild-from-Cassandra** or **full reindex** flows before production; Lucene indices are not upgraded in place from ES 6.8 to OpenSearch 1.3.

**Suggested staging checklist**

#. Provision a non-production cluster with the target Elassandra build (same C* + search versions as production).
#. Snapshot or otherwise record baseline index names, mappings, and critical CQL schemas.
#. Run your chosen migration path: **rebuild indices from Cassandra** (nodetool / Elassandra rebuild procedures as documented for your release) **or** **full reindex** into fresh OpenSearch 1.3–compatible indices.
#. Validate search correctness (spot queries, aggregations, per–DC routing if used) and operational metrics (heap, GC, repair).
#. Roll dashboards and REST clients to OpenSearch 7.10–style APIs; retire ES 6.x–only plugins.

Further reading
---------------

* :ref:`cassandra_fork_inventory` — Cassandra-side commit inventory and 4.0 branch strategy.
* :ref:`cassandra_40_rebase` — step-by-step patch export, 4.0 clone, and ``git am`` workflow.
* :ref:`cassandra_40_jvm_port` — Elassandra Java integration points for Cassandra 4.0.
* :ref:`opensearch_porting_guide` — developer map for rebasing onto OpenSearch 1.3.x.
* Repository scripts: ``scripts/check-cassandra-submodule.sh`` (version alignment), ``scripts/use-cassandra-40-submodule.sh`` (move submodule to Cassandra 4.0), ``scripts/clone-opensearch-upstream.sh`` / ``scripts/opensearch-port-bootstrap.sh`` (OpenSearch **1.3.20** port branch), ``scripts/sync-elassandra-to-opensearch-sidecar.sh`` / ``scripts/rewrite-elassandra-imports-for-opensearch.sh`` (copy ``org.elassandra.*`` into the side-car), ``scripts/build-elassandra-cassandra-jar.sh`` (Ant Cassandra jar for the side-car classpath), ``scripts/sync-elassandra-fork-minimal-to-opensearch-sidecar.sh`` (minimal ``org.opensearch`` fork stubs), ``scripts/patch-opensearch-forbidden-deps-for-elassandra.sh`` (temporarily allow Guava in the side-car tree), ``scripts/opensearch-sidecar-compile-try.sh`` (runs ``:server:compileJava``, ``:test:framework:compileJava``, and ``:server:compileTestJava`` in the side-car; set ``OPENSEARCH_SIDECAR_TASKS=:server:compileJava`` to skip test compilation; uses ``gradle/opensearch-sidecar-elassandra.init.gradle`` and ``GRADLE_OPTS``), ``scripts/export-elassandra-mapper-fork-for-opensearch-merge.sh`` (export forked ``index/mapper`` for merge), ``scripts/list-elasticsearch-fork-touchpoints.sh`` (engine fork inventory), ``scripts/print-opensearch-port-pins.sh`` (target pins).

Packaging (when the OpenSearch port ships)
------------------------------------------

* Revisit tarball/deb/rpm naming and any process branding if you move from “Elasticsearch” to “OpenSearch” in user-visible strings.
* Rebuild container images from the merged tree; re-check JVM flags for Cassandra **4.0** plus the embedded search engine.
* Pins: ``./scripts/print-opensearch-port-pins.sh`` prints ``opensearch_port`` / ``lucene_opensearch`` from ``buildSrc/version.properties``; full artifact convergence is tracked in :ref:`opensearch_porting_guide`.
