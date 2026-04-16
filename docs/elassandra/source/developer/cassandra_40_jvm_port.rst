.. _cassandra_40_jvm_port:

Cassandra 4.0 JVM port (Elassandra integration code)
=====================================================

This repository now ships the **Cassandra 4.0.x + OpenSearch 1.3.x** line. This note remains useful as
an inventory of the API shifts that were required to move the Elassandra integration from the old
3.11 / Elasticsearch stack to the merged modern baseline:

#. Run ``scripts/use-cassandra-40-submodule.sh`` — aligns ``buildSrc/version.properties`` ``cassandra=`` with ``server/cassandra/build.xml`` ``base.version`` and checks out ``cassandra-4.0.x-elassandra``.
#. Port Elassandra-specific classes against **4.0 APIs** (types and method signatures differ from 3.11; mechanical rename is not enough).

Representative API shifts (non-exhaustive)
------------------------------------------

* ``org.apache.cassandra.config.CFMetaData`` → ``org.apache.cassandra.schema.TableMetadata`` (and related schema types live under ``org.apache.cassandra.schema``).
* ``org.apache.cassandra.config.ColumnDefinition`` → ``org.apache.cassandra.schema.ColumnMetadata``.
* Secondary index ``Index.indexerFor`` — parameters moved from ``PartitionColumns`` / ``OpOrder.Group`` to ``RegularAndStaticColumns`` / ``WriteContext`` (see upstream ``org.apache.cassandra.index.Index`` in the 4.0 sources).
* ``ExtendedElasticSecondaryIndex.validateOptions`` — prefer the overload taking ``TableMetadata`` when both static methods exist.

Primary touchpoints in this repo
---------------------------------

* ``org.elassandra.index.ElasticSecondaryIndex`` / ``ExtendedElasticSecondaryIndex``
* ``org.elassandra.cluster.SchemaManager``, ``QueryManager``, ``SchemaListener``, ``ColumnDescriptor``
* ``org.opensearch.cluster.service.ClusterService`` and metadata services that bridge C* schema to OpenSearch mappings
* Tests under ``server/src/test/java/org/elassandra/``

For current-tree validation, run ``./scripts/check-cassandra-submodule.sh`` and ``./gradlew :server:compileJava`` with **Java 11+**.

**Merged in-tree:** ``ElasticSecondaryIndex`` / ``ExtendedElasticSecondaryIndex`` are updated for Cassandra **4.0** index APIs (``TableMetadata``, ``ColumnMetadata``, ``RegularAndStaticColumns``, ``WriteContext``). The current merged tree uses OpenSearch bridge classes under ``org.opensearch.cluster`` / ``org.opensearch.index.mapper`` together with ``org.elassandra.*`` integration code.
