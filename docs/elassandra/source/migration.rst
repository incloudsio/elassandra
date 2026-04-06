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

Further reading
---------------

* :ref:`cassandra_fork_inventory` — Cassandra-side commit inventory and 4.0 branch strategy.
* :ref:`cassandra_40_rebase` — step-by-step patch export, 4.0 clone, and ``git am`` workflow.
* :ref:`opensearch_porting_guide` — developer map for rebasing onto OpenSearch 1.3.x.
* Repository scripts: ``scripts/check-cassandra-submodule.sh`` (version alignment) and ``scripts/clone-opensearch-upstream.sh`` (clone OpenSearch **1.3.20** for porting).
